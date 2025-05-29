import SwiftUI

@main
struct SiteSincApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .preferredColorScheme(.light)
        }.modelContainer(for: [RFIDraft.self, SelectedDrawing.self])
    }
}
