import SwiftUI

struct ContentView: View {
    // State to manage authentication and tenant selection
    @State private var token: String? = UserDefaults.standard.string(forKey: "authToken")
    @State private var selectedTenantId: Int? = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int
    @State private var isSelectingTenant = false
    @State private var tenants: [User.UserTenant]?
    @State private var errorMessage: String?

    var body: some View {
        // If not authenticated, show LoginView
        if token == nil {
            LoginView(onLoginComplete: { newToken, user in
                print("ContentView: onLoginComplete called with token=\(newToken), user=\(user)")
                UserDefaults.standard.set(newToken, forKey: "authToken")
                self.token = newToken
                self.tenants = user.tenants

                // Handle tenant selection logic
                if let tenants = user.tenants, !tenants.isEmpty {
                    if tenants.count == 1, let firstTenant = tenants.first, let tenant = firstTenant.tenant, let tenantId = Optional.some(tenant.id) {
                        print("Auto-selecting tenant: \(tenantId)")
                        APIClient.selectTenant(token: newToken, tenantId: tenantId) { result in
                            switch result {
                            case .success(let (updatedToken, updatedUser)):
                                print("Auto-selection successful: updatedToken=\(updatedToken), updatedUser=\(updatedUser)")
                                UserDefaults.standard.set(updatedToken, forKey: "authToken")
                                UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                                self.token = updatedToken
                                self.selectedTenantId = tenantId
                                self.isSelectingTenant = false
                            case .failure(let err):
                                print("Auto-select tenant failed: \(err)")
                                self.errorMessage = "Failed to select tenant: \(err.localizedDescription). Please try again or logout."
                                self.isSelectingTenant = true
                            }
                        }
                    } else {
                        print("Multiple tenants found, showing SelectTenantView")
                        self.isSelectingTenant = true
                    }
                } else {
                    print("No tenants found, forcing logout")
                    self.errorMessage = "No organizations found. Please contact support."
                    logout()
                }
            })
        }
        // If authenticated and a tenant is selected, show ProjectListView
        else if let tenantId = selectedTenantId, let token = token {
            ProjectListView(token: token, tenantId: tenantId, onLogout: {
                print("ProjectListView: Logging out")
                logout()
            })
        }
        // If authenticated but no tenant is selected, show tenant selection or error
        else {
            if let errorMessage = errorMessage {
                VStack {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Button("Retry") {
                        self.errorMessage = nil
                        self.isSelectingTenant = false
                        if let token = token, let tenants = tenants, tenants.count == 1, let firstTenant = tenants.first, let tenant = firstTenant.tenant, let tenantId = Optional.some(tenant.id) {
                            APIClient.selectTenant(token: token, tenantId: tenantId) { result in
                                switch result {
                                case .success(let (updatedToken, _)):
                                    UserDefaults.standard.set(updatedToken, forKey: "authToken")
                                    UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                                    self.token = updatedToken
                                    self.selectedTenantId = tenantId
                                    self.isSelectingTenant = false
                                case .failure(let err):
                                    self.errorMessage = "Failed to select tenant: \(err.localizedDescription)"
                                    self.isSelectingTenant = true
                                }
                            }
                        }
                    }
                    Button("Logout") {
                        logout()
                    }
                }
            } else {
                SelectTenantView(
                    isPresented: $isSelectingTenant,
                    token: token!,
                    initialTenants: tenants,
                    onSelectTenant: { newToken, user in
                        print("ContentView: Tenant selected with token=\(newToken), user=\(user)")
                        UserDefaults.standard.set(newToken, forKey: "authToken")
                        let tenantId = user.tenantId ?? 0
                        UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                        self.token = newToken
                        self.selectedTenantId = tenantId
                        self.isSelectingTenant = false
                    },
                    onLogout: {
                        print("SelectTenantView: Logging out")
                        logout()
                    }
                )
            }
        }
    }

    private func logout() {
        print("ContentView: Logging out")
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "selectedTenantId")
        self.token = nil
        self.selectedTenantId = nil
        self.tenants = nil
        self.isSelectingTenant = false
        self.errorMessage = nil
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
