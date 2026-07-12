import SwiftUI
import LocalAuthentication // For Face ID

struct LoginView: View {
    private enum Field: Hashable {
        case email
        case password
        case resetEmail
    }

    @EnvironmentObject var sessionManager: SessionManager
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var canUseFaceID: Bool = false
    @State private var error = ""
    @State private var isLoading = false // Shared loading state
    @State private var showResetDialog = false
    @State private var resetEmail = ""
    @State private var resetError = ""
    @State private var resetSuccess = false
    @State private var resetLoading = false
    @FocusState private var focusedField: Field?

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
                    await MainActor.run {
                        isLoading = false
                        // If Face ID isn't already enabled on this device, offer to enable it
                        // now (via a prompt shown over whatever screen we land on next) rather
                        // than asking on the login form itself. This is a no-op if credentials
                        // are already stored (e.g. this login came from the Face ID button).
                        sessionManager.noteSuccessfulPasswordLogin(email: lowercaseEmail, password: password)
                        // Track successful login
                        AnalyticsManager.shared.trackLogin(method: "email")
                        if let user = sessionManager.user {
                            AnalyticsManager.shared.setUserId(user.id)
                        }
                        AnalyticsManager.shared.setTenantId(sessionManager.selectedTenantId)
                    }
                } catch {
                    await MainActor.run {
                        self.error = Self.loginErrorMessage(for: error)
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

    /// Maps a login failure to a user-facing message using typed APIError cases
    /// instead of fragile string matching on the error description. Not private
    /// so other password-verification flows (e.g. enabling Face ID from Settings)
    /// can reuse the same messaging.
    static func loginErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .tokenExpired, .forbidden:
                // The login endpoint reports invalid credentials via a 401/403.
                return "Invalid email or password"
            default:
                return apiError.displayMessage
            }
        }
        return "Login failed: \(error.localizedDescription)"
    }

    private func attemptFaceIDLogin() {
        guard let savedEmail = KeychainHelper.getEmail(),
              KeychainHelper.hasStoredPassword() else {
            self.error = "No saved credentials. Please log in with email/password first to enable Face ID."
            self.canUseFaceID = false
            return
        }

        let context = LAContext()
        var policyError: NSError?
        let reason = "Log in to SiteSinc with Face ID."

        self.isLoading = true
        self.error = ""

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            self.isLoading = false
            self.canUseFaceID = false
            if let laPolicyError = policyError as? LAError, laPolicyError.code == .biometryLockout {
                self.error = "Face ID locked. Please use email/password."
            }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
            Task { @MainActor in
                if success {
                    print("LoginView: Face ID Authentication successful.")
                    guard let savedPassword = KeychainHelper.getPassword() else {
                        self.error = "Face ID login failed: No saved credentials. Please log in with email/password first to enable Face ID."
                        self.isLoading = false
                        self.canUseFaceID = false
                        return
                    }

                    self.email = savedEmail
                    self.password = savedPassword

                    print("LoginView: Proceeding with login after Face ID success using stored credentials.")
                    self.handleLogin()
                } else {
                    if let authError = authenticationError as? LAError {
                        switch authError.code {
                        case .authenticationFailed:
                            self.error = "Face ID authentication failed. Please use email/password."
                        case .userCancel:
                            self.error = ""
                        case .userFallback:
                            self.error = "Please enter your email and password."
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
                    self.isLoading = false
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

                ScrollView {
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

                    if canUseFaceID {
                        Button(action: {
                            attemptFaceIDLogin()
                        }) {
                            HStack {
                                Image(systemName: "faceid")
                                Text("Sign in with Face ID")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(Color(hex: "#635bff"))
                            .cornerRadius(8)
                        }
                        .disabled(isLoading)
                    }

                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .textContentType(.username)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.black)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.black)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
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
                        focusedField = nil
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
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
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
                        .focused($focusedField, equals: .resetEmail)
                        .submitLabel(.go)
                        .onSubmit { handleResetPassword() }

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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
            }
            .onAppear {
                // Track screen view
                AnalyticsManager.shared.trackScreenView("Login")

                // Always reset interaction state when the screen appears after logout /
                // session expiry. A stuck isLoading or focus value is what made the fields
                // look frozen after signing out.
                isLoading = false
                focusedField = nil
                showResetDialog = false

                // Prefill the last-used email so users don't retype it every time.
                if email.isEmpty, let savedEmail = KeychainHelper.getEmail() {
                    email = savedEmail
                }

                if error.isEmpty, let sessionError = sessionManager.errorMessage, !sessionError.isEmpty {
                    error = sessionError
                    sessionManager.errorMessage = nil
                }

                // Only offer the explicit Face ID button if credentials were previously
                // saved AND the device actually supports biometrics. We deliberately do
                // NOT auto-trigger Face ID here anymore — the user taps the button.
                let context = LAContext()
                let biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
                canUseFaceID = biometricsAvailable && KeychainHelper.hasStoredPassword() && KeychainHelper.getEmail() != nil
            }
        }
    }
}




#Preview {
    LoginView()
        .environmentObject(SessionManager())
}
