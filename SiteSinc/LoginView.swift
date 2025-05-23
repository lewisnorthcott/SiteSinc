import SwiftUI

struct LoginView: View {
    @State private var email = "lewis.northcott@gmail.com"
    @State private var password = "Sln_2022!"
    @State private var error = ""
    @State private var isLoading = false
    @State private var showResetDialog = false
    @State private var resetEmail = ""
    @State private var resetError = ""
    @State private var resetSuccess = false
    @State private var resetLoading = false
    let onLoginComplete: (String, User) -> Void

    private func handleLogin() {
        isLoading = true
        error = ""
        let lowercaseEmail = email.lowercased()
        APIClient.login(email: lowercaseEmail, password: password) { result in
            switch result {
            case .success(let (token, user)):
                print("Login successful: token=\(token), user=\(user)")
                
                // Check if user has any tenants
                if let tenants = user.tenants, !tenants.isEmpty, let firstTenant = tenants.first,
                   let tenantId = firstTenant.tenantId ?? firstTenant.tenant?.id {
                    // Auto-select the first tenant
                    APIClient.selectTenant(token: token, tenantId: tenantId) { selectResult in
                        switch selectResult {
                        case .success(let (newToken, updatedUser)):
                            print("Auto-selected tenant: token=\(newToken), user=\(updatedUser)")
                            onLoginComplete(newToken, updatedUser)
                        case .failure(let err):
                            error = "Failed to auto-select tenant: \(err.localizedDescription)"
                            print("Auto-select tenant failed: \(error)")
                            isLoading = false
                        }
                    }
                } else {
                    // No tenants available or no valid tenant ID
                    error = "No tenants available for this user or invalid tenant data"
                    print("No tenants available or invalid tenant data: \(error)")
                    isLoading = false
                }
            case .failure(let err):
                if err.localizedDescription.contains("401") {
                    error = "Invalid email or password"
                } else {
                    error = "Login failed: \(err.localizedDescription)"
                }
                print("Login failed: \(error)")
                isLoading = false
            }
        }
    }

    private func handleResetPassword() {
        resetLoading = true
        resetError = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if resetEmail.isEmpty || !resetEmail.contains("@") {
                resetError = "Invalid email"
            } else {
                resetSuccess = true
                resetEmail = ""
            }
            resetLoading = false
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
    LoginView(onLoginComplete: { token, user in
        print("Login completed with token: \(token), user: \(user)")
    })
}
