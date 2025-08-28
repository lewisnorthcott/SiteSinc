// TenantSelectionView.swift
import SwiftUI

struct TenantSelectionView: View {
    let token: String
    let onSelectTenant: (Int, String) -> Void
    let tenants: [Tenant]? // Keep as let for input, but use as initial value
    @EnvironmentObject var sessionManager: SessionManager
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
        do {
            let t = try await APIClient.fetchTenants(token: token)
            await MainActor.run {
                localTenants = t
                if localTenants.count == 1 {
                    selectedTenantId = localTenants[0].id
                    selectTenant(localTenants[0].id)
                }
                isLoading = false
            }
        } catch APIError.tokenExpired {
            await MainActor.run {
                sessionManager.handleTokenExpiration()
            }
        } catch APIError.forbidden {
            await MainActor.run {
                sessionManager.handleTokenExpiration()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load tenants: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func selectTenant(_ tenantId: Int) {
        Task {
            do {
                let (newToken, _) = try await APIClient.selectTenant(token: token, tenantId: tenantId)
                await MainActor.run {
                    onSelectTenant(tenantId, newToken)
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch APIError.forbidden {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to select tenant: \(error.localizedDescription)"
                }
            }
        }
    }
}
