import SwiftUI

@main
struct SiteSincApp: App {
    @State private var token: String? = UserDefaults.standard.string(forKey: "authToken")
    @State private var selectedTenantId: Int? = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int

    var body: some Scene {
        WindowGroup {
            ContentView(token: $token, selectedTenantId: $selectedTenantId)
        }.modelContainer(for: [RFIDraft.self, SelectedDrawing.self])
    }
}
