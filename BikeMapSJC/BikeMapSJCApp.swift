import SwiftUI
import UserNotifications
import CoreLocation
import AVFoundation

/// Plays a brief bird-chirp on first launch of this process — parity with
/// BikeMap SP. Held as a static property so the player object outlives the
/// call site. Deactivates the audio session as soon as the clip finishes so
/// other apps' audio (music, podcasts) resumes at full volume.
enum LaunchSound {
    private static var player: AVAudioPlayer?
    private static var hasPlayed = false

    static func playOnce() {
        guard !hasPlayed else { return }
        hasPlayed = true
        guard let url = Bundle.main.url(forResource: "launch_bird", withExtension: "m4a") else {
            print("LaunchSound: launch_bird.m4a not found in bundle")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                                options: [.mixWithOthers, .duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                let p = try AVAudioPlayer(contentsOf: url)
                p.volume = 0.8
                p.prepareToPlay()
                p.play()
                player = p
                let releaseAfter = p.duration + 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + releaseAfter) {
                    player = nil
                    try? AVAudioSession.sharedInstance().setActive(
                        false, options: [.notifyOthersOnDeactivation]
                    )
                }
            } catch {
                print("LaunchSound error: \(error)")
            }
        }
    }
}

@main
struct BikeMapSJCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Bird-chirp once per process — same clip as BikeMap SP.
        LaunchSound.playOnce()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if appState.currentUserName != nil || appState.guestAccess {
                        ContentView(appState: appState)
                            .transition(.opacity)
                    } else {
                        WelcomeView(appState: appState)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: appState.currentUserName)
                .animation(.easeInOut(duration: 0.3), value: appState.guestAccess)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .task {
                // Splash visível por ~1s — tempo suficiente para o pulso da logo
                // sem bloquear a abertura do mapa.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                showSplash = false
            }
            .onAppear {
                appDelegate.appState = appState
                appState.requestPushPermission()
            }
            // Navigate to POI when notification is tapped
            .onChange(of: appState.notificationTargetPOI) { _, poi in
                // ContentView observes this via appState directly
            }
            // Clear the app icon badge whenever the app becomes active
            // so the red dot disappears after the user has seen the alert.
            // Also auto-open the latest unread furto so users who open the
            // app from the home screen (not via push tap) land on the new
            // stolen-bike point.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    AppDelegate.clearBadge()
                    Task { await appState.openLatestUnreadFurtoIfAny() }
                    // Re-check the profile so admin block/delete actions
                    // log the user out on next foreground.
                    if let uid = appState.currentUserId {
                        Task { await appState.fetchProfile(userId: uid) }
                    }
                }
            }
        }
    }
}

// MARK: - App Delegate (push notifications)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when APNs gives us a device token
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        appState?.savePushToken(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for push: \(error)")
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap → navigate to POI
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let latStr = info["lat"] as? String, let lngStr = info["lng"] as? String,
           let lat = Double(latStr), let lng = Double(lngStr) {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let title = info["poi_title"] as? String ?? "Bike desaparecida"
            let desc  = info["poi_description"] as? String ?? ""
            let poiId = info["poi_id"] as? String ?? ""
            let poi   = POI(id: poiId, type: POIType.furto.rawValue,
                            lat: lat, lng: lng,
                            title: title, description: desc,
                            author: "", createdAt: nil)
            DispatchQueue.main.async {
                self.appState?.notificationTargetPOI = poi
                AppDelegate.clearBadge()
            }
        }
        completionHandler()
    }

    /// Clear the app icon badge. Called on notification tap and when the
    /// app becomes active (scenePhase → .active) so the red dot disappears
    /// after the user has seen the new theft alert.
    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error { print("clearBadge error: \(error)") }
        }
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .opacity(pulse ? 1.0 : 0.35)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
        }
    }
}
