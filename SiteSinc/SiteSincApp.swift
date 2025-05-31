import SwiftUI

@main
struct SiteSincApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var networkStatusManager = NetworkStatusManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(networkStatusManager) // Inject NetworkStatusManager before applying the modifier
                .preferredColorScheme(.light)
                .offlineBanner() // Apply the banner after injecting the environment object
        }
        .modelContainer(for: [RFIDraft.self, SelectedDrawing.self])
    }
}
