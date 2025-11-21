import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        let tokenExists = sessionManager.token != nil
        let tenantId = sessionManager.selectedTenantId
        let isSelectingTenant = sessionManager.isSelectingTenant
        
        let _ = print("🔄 [ContentView] Building body - token: \(tokenExists ? "exists" : "nil"), tenantId: \(tenantId?.description ?? "nil"), isSelectingTenant: \(isSelectingTenant)")
        
        return ZStack {
            // Background to ensure something is rendered
            Color(.systemBackground)
                .ignoresSafeArea()
            
            Group {
            // Main content
            if sessionManager.token == nil {
                let _ = print("🔄 [ContentView] Showing LoginView (no token)")
                LoginView()
            } else if let tenantId = sessionManager.selectedTenantId, let validToken = sessionManager.token {
                let _ = print("🔄 [ContentView] Showing ProjectListView (token + tenantId: \(tenantId))")
                ProjectListView(token: validToken, tenantId: tenantId, onLogout: {
                    print("ProjectListView: Logging out")
                    sessionManager.logout()
                })
            } else if sessionManager.token != nil && (sessionManager.selectedTenantId == nil || sessionManager.isSelectingTenant) {
                let _ = print("🔄 [ContentView] Showing tenant selection (token exists but no tenant)")
                if let currentErrorMessage = sessionManager.errorMessage {
                    let _ = print("🔄 [ContentView] Showing error view: \(currentErrorMessage)")
                    VStack(spacing: 20) {
                        Text("Error")
                            .font(.title)
                        Text(currentErrorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Retry Login") {
                            sessionManager.logout()
                        }
                        .padding()
                        Button("Logout") {
                            sessionManager.logout()
                        }
                        .padding()
                    }
                } else {
                    let _ = print("🔄 [ContentView] Showing SelectTenantView")
                    SelectTenantView(
                        isPresented: .constant(true),
                        token: sessionManager.token!,
                        initialTenants: sessionManager.tenants,
                        onSelectTenant: { newToken, user in
                            Task {
                                try await sessionManager.selectTenant(token: newToken, tenantId: user.tenantId ?? 0)
                            }
                        },
                        onLogout: {
                            print("SelectTenantView: Logging out")
                            sessionManager.logout()
                        }
                    )
                }
            } else {
                let _ = print("🔄 [ContentView] Fallback to LoginView")
                LoginView()
            }
            }
        }
        .onAppear {
            print("🔄 [ContentView] onAppear called")
            // Set up notification manager with session manager
            notificationManager.sessionManager = sessionManager
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SessionManager())
            .environmentObject(NetworkStatusManager.shared)
            .environmentObject(NotificationManager.shared)
    }
}
