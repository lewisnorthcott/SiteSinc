import SwiftUI

struct LoginView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var email: String = {
            #if DEBUG
            return "lewis.northcott@gmail.com"
            #else
            return ""
            #endif
        }()
        @State private var password: String = {
            #if DEBUG
            return "Sln_2022!"
            #else
            return ""
            #endif
        }()
    @State private var error = ""
    @State private var isLoading = false
    @State private var showResetDialog = false
    @State private var resetEmail = ""
    @State private var resetError = ""
    @State private var resetSuccess = false
    @State private var resetLoading = false
    
    

    private func handleLogin() {
        guard !email.isEmpty, !password.isEmpty else {
            error = "Please enter email and password."
            return
        }

        isLoading = true
        error = ""
        let lowercaseEmail = email.lowercased()

        Task {
            // Wait for the initial network status update
            let isNetworkAvailable = await NetworkMonitor.shared.waitForInitialNetworkStatus()
            print("LoginView: Network available: \(isNetworkAvailable)")

            if isNetworkAvailable {
                // Online login
                print("LoginView: Attempting online login")
                do {
                    try await sessionManager.login(email: lowercaseEmail, password: password)
                    _ = KeychainHelper.saveEmail(lowercaseEmail)
                    _ = KeychainHelper.savePassword(password)
                    await MainActor.run {
                        isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        if error.localizedDescription.contains("401") {
                            self.error = "Invalid email or password"
                        } else {
                            self.error = "Login failed: \(error.localizedDescription)"
                        }
                        print("Login failed: \(self.error)")
                        isLoading = false
                    }
                }
            } else {
                // Offline login
                print("LoginView: Network unavailable, attempting offline login")
                if let savedEmail = KeychainHelper.getEmail(),
                   let savedPassword = KeychainHelper.getPassword(),
                   savedEmail == lowercaseEmail,
                   savedPassword == password,
                   let token = KeychainHelper.getToken(),
                   let cachedTenants = sessionManager.getCachedTenants() {
                    print("LoginView: Offline login successful")
                    await MainActor.run {
                        sessionManager.token = token
                        sessionManager.tenants = cachedTenants
                        if let selectedTenantId = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int {
                            sessionManager.selectedTenantId = selectedTenantId
                            sessionManager.isSelectingTenant = false
                        } else if cachedTenants.count == 1, let tenant = cachedTenants.first?.tenant {
                            sessionManager.selectedTenantId = tenant.id
                            UserDefaults.standard.set(tenant.id, forKey: "selectedTenantId")
                            sessionManager.isSelectingTenant = false
                        } else {
                            sessionManager.isSelectingTenant = true
                        }
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        error = "Offline login failed: Invalid credentials or no cached session"
                        isLoading = false
                        print("LoginView: Offline login failed: \(error)")
                    }
                }
            }
        }
    }

    private func handleResetPassword() {
        resetLoading = true
        resetError = ""
        Task {
            do {
                let message = try await APIClient.requestPasswordReset(email: resetEmail)
                await MainActor.run {
                    resetSuccess = true
                    resetEmail = ""
                    resetLoading = false
                    print("Reset password successful: \(message)")
                }
            } catch {
                await MainActor.run {
                    if resetEmail.isEmpty || !resetEmail.contains("@") {
                        resetError = "Invalid email"
                    } else {
                        resetError = "Failed to send reset link: \(error.localizedDescription)"
                    }
                    resetLoading = false
                    print("Reset password failed: \(resetError)")
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    HStack(spacing: 0) {
                        Text("Site")
                            .font(.title)
                            .fontWeight(.regular)
                        Text("Sinc")
                            .font(.title)
                            .fontWeight(.regular)
                            .foregroundColor(Color(hex: "#635bff"))
                    }

                    VStack(spacing: 8) {
                        Text("Welcome back")
                            .font(.title3)
                            .fontWeight(.regular)
                        Text("Sign in to access your account")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    if !error.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    TextField("Email", text: $email)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.black)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disabled(isLoading)
                        .onSubmit { handleLogin() }

                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.black)
                        .disabled(isLoading)
                        .onSubmit { handleLogin() }

                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            showResetDialog = true
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                        .disabled(isLoading)
                    }

                    Button(action: {
                        withAnimation(.spring()) {
                            handleLogin()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.5)
                            }
                            Text(isLoading ? "Signing in..." : "SIGN IN")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .tracking(1)
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .scaleEffect(isLoading ? 0.98 : 1.0)
                    }
                    .disabled(isLoading)

                    Text("Don't have an account? ")
                        .font(.caption)
                        .foregroundColor(.gray) +
                    Text("Register")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 400)
            }
            .ignoresSafeArea(.keyboard)
            .sheet(isPresented: $showResetDialog) {
                VStack(spacing: 16) {
                    Text("Reset Password")
                        .font(.title3)
                        .fontWeight(.regular)
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    if !resetError.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                            Text(resetError)
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    }

                    if resetSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("If an account exists with this email, you will receive password reset instructions.")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    }

                    TextField("Email", text: $resetEmail)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.black)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disabled(resetLoading)

                    Button(action: {
                        withAnimation {
                            handleResetPassword()
                        }
                    }) {
                        HStack {
                            if resetLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.5)
                            }
                            Text(resetLoading ? "Sending Reset Link..." : "Send Reset Link")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(resetLoading)

                    Button("Cancel") {
                        showResetDialog = false
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                }
                .padding(24)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(radius: 10)
                .frame(maxWidth: 400)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(SessionManager())
}
