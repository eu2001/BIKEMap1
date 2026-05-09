import SwiftUI

@main
struct BikeMapSJCApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
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
        }
    }
}
