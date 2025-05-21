import SwiftUI

@main
struct SiteSincApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }.modelContainer(for: [RFIDraft.self, SelectedDrawing.self])
    }
}
