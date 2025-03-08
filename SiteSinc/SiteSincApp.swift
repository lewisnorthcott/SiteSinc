// SiteSincApp.swift
import SwiftUI

@main
struct SiteSincApp: App {
    @State private var token: String? = nil // Force login by starting with nil
    @State private var selectedTenantId: Int? = nil

    var body: some Scene {
        WindowGroup {
            ContentView(token: $token, selectedTenantId: $selectedTenantId)
                .onAppear {
                    // Optional: Clear any existing token on app launch to force re-login
                    UserDefaults.standard.removeObject(forKey: "authToken")
                    UserDefaults.standard.removeObject(forKey: "selectedTenantId")
                }
        }
    }
}
