// TenantSelectionView.swift
import SwiftUI

struct TenantSelectionView: View {
    let token: String
    let onSelectTenant: (Int, String) -> Void
    let tenants: [Tenant]? // Keep as let for input, but use as initial value
    @State private var localTenants: [Tenant] = [] // State to manage tenants
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTenantId: Int?

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)

                VStack {
                    if isLoading {
                        ProgressView("Loading Tenants...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .padding()
                    } else if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    } else if localTenants.isEmpty {
                        Text("No tenants available")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        List(localTenants, id: \.id) { tenant in
                            Button(action: {
                                selectedTenantId = tenant.id
                            }) {
                                HStack {
                                    Text(tenant.name)
                                        .foregroundColor(.primary)
                                    if selectedTenantId == tenant.id {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding()
                            }
                        }
                        Button(action: {
                            if let tenantId = selectedTenantId {
                                selectTenant(tenantId)
                            }
                        }) {
                            Text("Select Tenant")
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(selectedTenantId == nil ? Color.gray : Color.blue)
                                .cornerRadius(8)
                                .disabled(selectedTenantId == nil)
                        }
                        .padding(.top)
                    }
                }
                .navigationTitle("Select Tenant")
            }
            .task {
                // Initialize with passed tenants, fetch only if nil
                if let initialTenants = tenants {
                    localTenants = initialTenants
                    if localTenants.count == 1 {
                        selectedTenantId = localTenants[0].id
                        selectTenant(localTenants[0].id)
                    }
                } else {
                    await fetchTenants()
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func fetchTenants() async {
        isLoading = true
        errorMessage = nil
        APIClient.fetchTenants(token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let t):
                    localTenants = t
                    if localTenants.count == 1 {
                        selectedTenantId = localTenants[0].id
                        selectTenant(localTenants[0].id)
                    }
                case .failure(let error):
                    errorMessage = "Failed to load tenants: \(error.localizedDescription)"
                }
            }
        }
    }

    private func selectTenant(_ tenantId: Int) {
        APIClient.selectTenant(token: token, tenantId: tenantId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (newToken, _)):
                    onSelectTenant(tenantId, newToken)
                case .failure(let error):
                    errorMessage = "Failed to select tenant: \(error.localizedDescription)"
                }
            }
        }
    }
}
