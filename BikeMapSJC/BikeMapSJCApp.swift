import SwiftUI
import UserNotifications
import CoreLocation

@main
struct BikeMapSJCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if appState.currentUserName != nil {
                        ContentView(appState: appState)
                            .transition(.opacity)
                    } else {
                        WelcomeView(appState: appState)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: appState.currentUserName)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
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
            let title = info["poi_title"] as? String ?? "Bike Theft"
            let desc  = info["poi_description"] as? String ?? ""
            let poiId = info["poi_id"] as? String ?? ""
            let poi   = POI(id: poiId, type: POIType.furto.rawValue,
                            lat: lat, lng: lng,
                            title: title, description: desc,
                            author: "", createdAt: nil)
            DispatchQueue.main.async {
                self.appState?.notificationTargetPOI = poi
            }
        }
        completionHandler()
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            GIFView(name: "welcome")
                .frame(width: 360, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        }
    }
}
