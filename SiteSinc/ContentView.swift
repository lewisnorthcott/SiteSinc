import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        if sessionManager.token == nil {
            LoginView()
        } else if let tenantId = sessionManager.selectedTenantId, let validToken = sessionManager.token {
            ProjectListView(token: validToken, tenantId: tenantId, onLogout: {
                print("ProjectListView: Logging out")
                sessionManager.logout()
            })
        } else if sessionManager.token != nil && (sessionManager.selectedTenantId == nil || sessionManager.isSelectingTenant) {
            if let currentErrorMessage = sessionManager.errorMessage {
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
            LoginView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SessionManager())
    }
}
