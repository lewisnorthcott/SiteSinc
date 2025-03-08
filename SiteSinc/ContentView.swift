// ContentView.swift
import SwiftUI

// ContentView.swift (relevant snippet)
struct ContentView: View {
    @Binding var token: String?
    @Binding var selectedTenantId: Int?

    @State private var tenants: [Tenant] = []
    @State private var isLoadingTenants = false

    var body: some View {
        if let token = token {
            if let tenantId = selectedTenantId {
                ProjectListView(token: token, tenantId: tenantId, onLogout: {
                    UserDefaults.standard.removeObject(forKey: "authToken")
                    UserDefaults.standard.removeObject(forKey: "selectedTenantId")
                    self.token = nil
                    self.selectedTenantId = nil
                })
            } else {
                if isLoadingTenants {
                    ProgressView("Loading Tenants...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .padding()
                } else if tenants.count > 1 {
                    TenantSelectionView(token: token, onSelectTenant: { tenantId, newToken in
                        UserDefaults.standard.set(newToken, forKey: "authToken")
                        UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                        self.token = newToken
                        selectedTenantId = tenantId
                    }, tenants: tenants) // This line is now valid
                } else {
                    ProjectListView(token: token, tenantId: tenants.first?.id ?? 0, onLogout: {
                        UserDefaults.standard.removeObject(forKey: "authToken")
                        UserDefaults.standard.removeObject(forKey: "selectedTenantId")
                        self.token = nil
                        self.selectedTenantId = nil
                    })
                }
            }
        } else {
            LoginView(onLogin: { newToken in
                UserDefaults.standard.set(newToken, forKey: "authToken")
                self.token = newToken
                Task {
                    await fetchTenants(token: newToken)
                }
            })
        }
    }

    private func fetchTenants(token: String) async {
        isLoadingTenants = true
        APIClient.fetchTenants(token: token) { result in
            DispatchQueue.main.async {
                isLoadingTenants = false
                switch result {
                case .success(let fetchedTenants):
                    tenants = fetchedTenants
                    print("Fetched tenants count: \(fetchedTenants.count)")
                    if fetchedTenants.count > 1 {
                        // Stay on TenantSelectionView
                    } else if fetchedTenants.count == 1 {
                        selectedTenantId = fetchedTenants[0].id
                    } else {
                        selectedTenantId = nil
                    }
                case .failure(let error):
                    print("Tenant fetch error: \(error)")
                }
            }
        }
    }

    @State private var errorMessage: String?


}
