import SwiftUI
import LocalAuthentication // For Face ID

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
    @State private var isLoading = false // Shared loading state
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

        // isLoading is typically set by the calling function (email/pass button or Face ID)
        // However, if called directly and isLoading isn't true, set it.
        if !isLoading { isLoading = true }
        error = ""
        let lowercaseEmail = email.lowercased()

        Task {
            let isNetworkAvailable = await NetworkMonitor.shared.waitForInitialNetworkStatus() //
            print("LoginView: Network available for email/password login: \(isNetworkAvailable)")

            if isNetworkAvailable {
                print("LoginView: Attempting online login")
                do {
                    try await sessionManager.login(email: lowercaseEmail, password: password) //
                    _ = KeychainHelper.saveEmail(lowercaseEmail) //
                    _ = KeychainHelper.savePassword(password) //
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
                print("LoginView: Network unavailable, attempting offline login")
                if let savedEmail = KeychainHelper.getEmail(), //
                   let savedPassword = KeychainHelper.getPassword(), //
                   savedEmail == lowercaseEmail,
                   savedPassword == password,
                   let token = KeychainHelper.getToken(), //
                   let cachedTenants = sessionManager.getCachedTenants() { //
                    print("LoginView: Offline login successful")
                    await MainActor.run {
                        sessionManager.token = token //
                        sessionManager.tenants = cachedTenants //
                        if let selectedTenantId = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int {
                            sessionManager.selectedTenantId = selectedTenantId //
                            sessionManager.isSelectingTenant = false //
                        } else if cachedTenants.count == 1, let tenant = cachedTenants.first?.tenant {
                            sessionManager.selectedTenantId = tenant.id //
                            UserDefaults.standard.set(tenant.id, forKey: "selectedTenantId")
                            sessionManager.isSelectingTenant = false //
                        } else {
                            sessionManager.isSelectingTenant = true //
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

    private func attemptFaceIDLogin() {
        let context = LAContext()
        var policyError: NSError?
        let reason = "Log in to SiteSinc with Face ID."

        // This function will be called on .onAppear, so set isLoading true here.
        // If called from a button later, this would also be appropriate.
        self.isLoading = true
        self.error = ""

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                Task {
                    await MainActor.run {
                        if success {
                            print("LoginView: Face ID Authentication successful.")
                            guard let savedEmail = KeychainHelper.getEmail(), //
                                  let savedPassword = KeychainHelper.getPassword() else { //
                                self.error = "Face ID login failed: No saved credentials. Please log in with email/password first to enable Face ID."
                                self.isLoading = false // Ensure isLoading is false if we can't proceed
                                return
                            }
                            
                            self.email = savedEmail
                            self.password = savedPassword // **SECURITY WARNING**

                            print("LoginView: Proceeding with login after Face ID success using stored credentials.")
                            self.handleLogin() // `handleLogin` will set isLoading = false on its completion.

                        } else {
                            // Face ID failed or was cancelled, allow manual login
                            if let authError = authenticationError as? LAError {
                                switch authError.code {
                                case .authenticationFailed:
                                    self.error = "Face ID authentication failed. Please use email/password."
                                case .userCancel:
                                    self.error = "Face ID cancelled. Please use email/password." // User cancelled
                                case .userFallback:
                                    self.error = "Please enter your email and password." // User chose password
                                case .biometryNotAvailable:
                                    self.error = "Face ID not available on this device."
                                case .biometryNotEnrolled:
                                    self.error = "Face ID not set up. Please use email/password."
                                case .biometryLockout:
                                    self.error = "Face ID locked out. Please use email/password."
                                default:
                                    self.error = "Face ID error. Please use email/password. (\(authError.localizedDescription))"
                                }
                            } else {
                                self.error = "Face ID error. Please use email/password. (\(authenticationError?.localizedDescription ?? "Unknown error"))"
                            }
                            print("LoginView: Face ID Authentication failed or cancelled: \(self.error)")
                            self.isLoading = false // Critical: allow manual input
                        }
                    }
                }
            }
        } else {
            // Face ID (biometrics) not available or not configured, allow manual login
            Task {
                await MainActor.run {
                    if let laPolicyError = policyError as? LAError {
                         switch laPolicyError.code {
                         case .biometryNotAvailable:
                             self.error = "" // Don't show error, just let them use password
                             print("LoginView: Face ID not available on this device.")
                         case .biometryNotEnrolled:
                             self.error = "" // Don't show error
                             print("LoginView: Face ID not set up on this device.")
                         case .biometryLockout:
                             self.error = "Face ID locked. Please use email/password."
                         default:
                             self.error = "" // Don't show error
                             print("LoginView: Face ID not configured: \(laPolicyError.localizedDescription)")
                         }
                    } else {
                        self.error = "" // Don't show error
                        print("LoginView: Face ID not available or configured. \(policyError?.localizedDescription ?? "")")
                    }
                    self.isLoading = false // Critical: allow manual input
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
                        // Face ID button is removed
                        Spacer() // Keep spacer if "Forgot password?" is on the right
                        Button("Forgot password?") {
                            showResetDialog = true
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                        .disabled(isLoading)
                    }

                    Button(action: {
                        withAnimation(.spring()) {
                            // Explicitly set isLoading for button press,
                            // as Face ID might not have run or might have set it to false.
                            if !isLoading { isLoading = true }
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
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 400)
            }
            .ignoresSafeArea(.keyboard)
            .sheet(isPresented: $showResetDialog) {
                // ... (your existing password reset sheet remains the same) ...
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
            .onAppear { // <-- Trigger Face ID check when the view appears
                // Only attempt Face ID if credentials have been saved previously
                // to avoid prompting new users unnecessarily.
                if KeychainHelper.getEmail() != nil && KeychainHelper.getPassword() != nil { //
                    attemptFaceIDLogin()
                }
            }
        }
    }
}




#Preview {
    LoginView()
        .environmentObject(SessionManager())
}
