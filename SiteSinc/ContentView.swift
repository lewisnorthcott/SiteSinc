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
                    sessionManager.logout(clearSavedCredentials: true)
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
                            // Keep saved credentials so Face ID / silent re-auth can still work.
                            sessionManager.logout()
                        }
                        .padding()
                        Button("Logout") {
                            // Explicit sign-out: fully clear saved credentials too.
                            sessionManager.logout(clearSavedCredentials: true)
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
                            sessionManager.logout(clearSavedCredentials: true)
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
        // Shown once, right after a successful password login, if Face ID isn't already
        // enabled on this device. Lives here (rather than on LoginView) so it can present
        // over whichever screen the user lands on next (project list, tenant picker, etc.)
        // instead of getting dismissed the instant the login screen swaps away.
        .alert(
            "Use Face ID to sign in faster?",
            isPresented: Binding(
                get: { sessionManager.shouldOfferFaceIDEnrollment },
                set: { newValue in
                    if !newValue {
                        sessionManager.dismissFaceIDEnrollmentPrompt()
                    }
                }
            )
        ) {
            Button("Enable") {
                sessionManager.enableFaceIDFromPendingCredentials()
            }
            Button("Not Now", role: .cancel) {
                sessionManager.dismissFaceIDEnrollmentPrompt()
            }
        } message: {
            Text("You can turn this on or off anytime from your Profile settings.")
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
