//
//  SessionManager.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 25/05/2025.
//

import SwiftUI

class SessionManager: ObservableObject {
    @Published var token: String? = KeychainHelper.getToken()
    @Published var selectedTenantId: Int? = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int
    @Published var tenants: [User.UserTenant]?
    @Published var errorMessage: String?
    @Published var isSelectingTenant: Bool = false
    
    private let tenantsKey = "cachedTeanants"
    
    func login(email: String, password: String) async throws {
        let (newToken, user) = try await APIClient.login(email: email, password: password)
        print("SessionManager: Login successful with token=\(newToken.prefix(10))..., user=\(user.email ?? "N/A")")
        
        guard KeychainHelper.saveToken(newToken) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save session"])
        }
        
        if let userTenants = user.tenants, let tenantsData = try? JSONEncoder().encode(userTenants) {
            UserDefaults.standard.set(tenantsData, forKey: tenantsKey)
        }
        
        await MainActor.run {
            self.token = newToken
            self.tenants = user.tenants
            
            if let userTenants = user.tenants, !userTenants.isEmpty {
                if userTenants.count == 1, let firstUserTenant = userTenants.first, let tenant = firstUserTenant.tenant {
                    let tenantIdToSelect = tenant.id
                    print("Attempting to auto-select single tenant ID: \(tenantIdToSelect)")
                    Task {
                        do {
                            let (updatedToken, _) = try await APIClient.selectTenant(token: newToken, tenantId: tenantIdToSelect)
                            await MainActor.run {
                                if KeychainHelper.saveToken(updatedToken) {
                                    self.token = updatedToken
                                } else {
                                    self.errorMessage = "Failed to update session. Please try again."
                                    self.logout()
                                    return
                                }
                                UserDefaults.standard.set(tenantIdToSelect, forKey: "selectedTenantId")
                                self.selectedTenantId = tenantIdToSelect
                                self.isSelectingTenant = false
                                self.errorMessage = nil
                            }
                        } catch {
                            await MainActor.run {
                                print("Auto-select tenant failed: \(error.localizedDescription)")
                                self.errorMessage = "Failed to select organization: \(error.localizedDescription)"
                                self.isSelectingTenant = true
                            }
                        }
                    }
                } else {
                    print("Multiple tenants (\(userTenants.count)) found or single tenant malformed, showing SelectTenantView")
                    self.isSelectingTenant = true
                    self.errorMessage = nil
                }
            } else {
                print("No tenants found for user \(user.email ?? "N/A")")
                self.errorMessage = "No organizations found for your account. Please contact support."
                self.isSelectingTenant = true
            }
        }
    }
    
    func getCachedTenants() -> [User.UserTenant]? {
        if let tenantsData = UserDefaults.standard.data(forKey: tenantsKey),
           let tenants = try? JSONDecoder().decode([User.UserTenant].self, from: tenantsData) {
            return tenants
        }
        return nil
    }

    func selectTenant(token: String, tenantId: Int) async throws {
        if await NetworkMonitor.shared.isNetworkAvailable() {
                let (newToken, user) = try await APIClient.selectTenant(token: token, tenantId: tenantId)
                print("SessionManager: Tenant selected with token=\(newToken.prefix(10))..., user=\(user.email ?? "N/A")")
                
                guard KeychainHelper.saveToken(newToken) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save session after tenant selection"])
                }
                
                let selectedTenantId = user.tenantId ?? 0
                guard selectedTenantId != 0 else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to confirm organization selection"])
                }
                
                await MainActor.run {
                    self.token = newToken
                    UserDefaults.standard.set(selectedTenantId, forKey: "selectedTenantId")
                    self.selectedTenantId = selectedTenantId
                    self.isSelectingTenant = false
                    self.errorMessage = nil
                }
            } else {
                // Offline tenant selection
                if let cachedTenants = getCachedTenants(), cachedTenants.contains(where: { $0.tenant?.id == tenantId }) {
                    await MainActor.run {
                        self.token = token
                        UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                        self.selectedTenantId = tenantId
                        self.isSelectingTenant = false
                        self.errorMessage = nil
                    }
                } else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Selected organization not found in cached data"])
                }
            }
        }
    

    func logout() {
        print("SessionManager: Logging out")
        _ = KeychainHelper.deleteToken()
        _ = KeychainHelper.deleteCredentials() // Add this to clear email and password
        UserDefaults.standard.removeObject(forKey: "selectedTenantId")
        UserDefaults.standard.removeObject(forKey: "cachedTenants") // Clear cached tenants
        self.token = nil
        self.selectedTenantId = nil
        self.tenants = nil
        self.isSelectingTenant = false
        self.errorMessage = nil
    }

    // Helper to handle token expiration
    func handleTokenExpiration() {
        print("SessionManager: Token expired, logging out")
        self.errorMessage = "Session expired. Please log in again."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.logout()
        }
    }
}
