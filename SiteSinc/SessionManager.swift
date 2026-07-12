//
//  SessionManager.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 25/05/2025.
//

import SwiftUI
import LocalAuthentication

class SessionManager: ObservableObject {
    /// Shared reference for components that need to trigger token refresh (e.g. OfflineSubmissionManager when sync gets 401).
    static weak var shared: SessionManager?

    @Published var token: String? = KeychainHelper.getToken()
    @Published var selectedTenantId: Int? = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int
    @Published var tenants: [User.UserTenant]?
    @Published var errorMessage: String?
    @Published var isSelectingTenant: Bool = false
    @Published var user: User?
    @Published var isLoadingPermissions: Bool = false
    @Published var isReauthInProgress: Bool = false
    // Set right after a successful *manual password* login when Face ID isn't already
    // enabled on this device, so the UI can offer to enable it once the user lands on
    // their next screen (rather than asking on the login form itself).
    @Published var shouldOfferFaceIDEnrollment: Bool = false
    /// Bumped on every logout so `LoginView` is recreated with clean field/focus state.
    @Published var loginFormID: Int = 0

    // Held only in memory, only long enough for the user to respond to the Face ID
    // enrollment prompt above. Never written to disk except via `KeychainHelper`
    // (biometric-gated) if the user explicitly opts in.
    private var pendingFaceIDEmail: String?
    private var pendingFaceIDPassword: String?

    private let tenantsKey = "cachedTeanants"
    private let userKey = "cachedUser"
    // Kept for diagnostics only — sessions are renewed via refresh tokens, not idle cutoffs.
    private let lastBackgroundedAtKey = "lastBackgroundedAt"
    private let faceIDEnrollmentDismissedKey = "faceIDEnrollmentDismissed"

    init() {
        Self.shared = self
        print("SessionManager: 🔄 Initializing SessionManager")
        print("SessionManager: 📱 Device: \(UIDevice.current.model) - \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        print("SessionManager: 📦 Bundle identifier: \(Bundle.main.bundleIdentifier ?? "nil")")

        // Check Keychain accessibility on init
        let keychainToken = KeychainHelper.getToken()
        print("SessionManager: 🔑 Token from Keychain: \(keychainToken?.prefix(10) ?? "nil") (length: \(keychainToken?.count ?? 0))")

        self.user = getCachedUser()
        // Load cached tenants on initialization
        self.tenants = getCachedTenants()

        print("SessionManager: 👤 Cached user: \(user?.email ?? "nil")")
        print("SessionManager: 🏢 Cached tenants count: \(tenants?.count ?? 0)")
        print("SessionManager: 🔐 Cached user permissions count: \(user?.permissions?.count ?? 0)")

        // If we have a cached user but no permissions, fetch them in background (don't block UI)
        if let cachedUser = user, (cachedUser.permissions?.isEmpty ?? true), keychainToken != nil {
            print("SessionManager: ⚠️  Cached user has no permissions, will fetch in background")
            // Fetch permissions asynchronously without blocking UI
            Task.detached(priority: .background) { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.fetchUserDetails()
                    print("SessionManager: ✅ Permissions fetched in background")
                } catch {
                    print("SessionManager: ❌ Failed to fetch permissions on init: \(error)")
                }
            }
        }
    }
    
    // Record the time we were backgrounded (used for logging / future policy only).
    func appDidEnterBackground() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: lastBackgroundedAtKey)
    }

    // On foreground: validate the access token; if expired, refresh via refresh token.
    // Do not force-logout solely based on idle duration — refresh tokens keep the session alive.
    @MainActor
    func appDidBecomeActive() async {
        defer { UserDefaults.standard.removeObject(forKey: lastBackgroundedAtKey) }
        guard token != nil else { return }
        await validateSessionOnForeground()
    }

    // Validate the current token with backend; if invalid, attempt refresh-token renewal.
    @MainActor
    func validateSessionOnForeground() async {
        guard let currentToken = token else { return }

        // Check if we need to refresh permissions
        let needsPermissionRefresh = user?.permissions?.isEmpty ?? true
        print("SessionManager: 🔍 Token validation - needs permission refresh: \(needsPermissionRefresh)")

        // Use a lightweight endpoint to verify token
        guard let url = URL(string: "\(APIClient.baseURL)/auth/test-token") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            switch http.statusCode {
            case 200:
                // Token is valid - ensure permissions are fresh if needed
                if needsPermissionRefresh {
                    print("SessionManager: 🔄 Token valid but permissions empty - fetching user details")
                    Task { try? await self.fetchUserDetails() }
                }
                return
            case 401, 403:
                if await attemptSilentReauth() {
                    self.errorMessage = nil
                } else {
                    handleTokenExpiration()
                }
            default:
                return
            }
        } catch {
            // Network failures are ignored here; other flows will surface errors
            return
        }
    }

    /// Single-flight refresh so parallel 401 retries share one `/auth/refresh-token` call
    /// and do not burn a rotated refresh token.
    private var inFlightRefreshTask: Task<Bool, Never>?

    // Renew the access token using the stored refresh token. No password re-login.
    func attemptSilentReauth() async -> Bool {
        if let inFlightRefreshTask {
            return await inFlightRefreshTask.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performRefreshTokenReauth()
        }
        inFlightRefreshTask = task
        let result = await task.value
        inFlightRefreshTask = nil
        return result
    }

    private func performRefreshTokenReauth() async -> Bool {
        await MainActor.run { self.isReauthInProgress = true }
        defer { Task { @MainActor in self.isReauthInProgress = false } }

        guard let refreshToken = KeychainHelper.getRefreshToken(), !refreshToken.isEmpty else {
            print("SessionManager: ❌ Silent re-auth failed - no refresh token stored")
            return false
        }

        do {
            let (newAccessToken, newRefreshToken) = try await APIClient.refreshAccessToken(refreshToken: refreshToken)
            guard KeychainHelper.saveSessionTokens(accessToken: newAccessToken, refreshToken: newRefreshToken) else {
                print("SessionManager: ❌ Silent re-auth failed - could not save rotated tokens")
                return false
            }

            await MainActor.run {
                self.token = newAccessToken
                self.errorMessage = nil
                // Refresh keeps the existing tenant context from the server session.
                if self.selectedTenantId == nil,
                   let savedTenantId = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int {
                    self.selectedTenantId = savedTenantId
                }
                self.isSelectingTenant = self.selectedTenantId == nil
                print("SessionManager: ✅ Refresh-token re-auth successful")
            }

            // Refresh permissions if we have a tenant and they're missing
            let needsPermissionRefresh = await MainActor.run { self.user?.permissions?.isEmpty ?? true }
            let hasTenant = await MainActor.run { self.selectedTenantId != nil }
            if hasTenant, needsPermissionRefresh {
                await MainActor.run { self.isLoadingPermissions = true }
                do {
                    try await fetchUserDetails()
                } catch {
                    print("SessionManager: ⚠️ Refresh succeeded but permission fetch failed: \(error)")
                    await MainActor.run { self.isLoadingPermissions = false }
                }
            }
            return true
        } catch {
            print("SessionManager: ❌ Refresh-token re-auth failed: \(error)")
            return false
        }
    }
    
    func login(email: String, password: String) async throws {
        print("SessionManager: Starting login for email: \(email)")
        print("SessionManager: Device info - Model: \(await UIDevice.current.model), System: \(await UIDevice.current.systemName) \(await UIDevice.current.systemVersion)")
        let bundleId = Bundle.main.bundleIdentifier ?? "nil"
        print("SessionManager: Bundle identifier: \(bundleId)")

        let (newToken, refreshToken, user) = try await APIClient.login(email: email, password: password)
        print("SessionManager: Login successful with token=\(newToken.prefix(10))..., user=\(user.email ?? "N/A")")
        print("SessionManager: User permissions count: \(user.permissions?.count ?? 0)")
        print("SessionManager: User roles count: \(user.roles?.count ?? 0)")

        print("SessionManager: Attempting to save access + refresh tokens to Keychain...")
        guard KeychainHelper.saveSessionTokens(accessToken: newToken, refreshToken: refreshToken) else {
            print("SessionManager: ❌ Failed to save session tokens to Keychain!")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save session"])
        }
        print("SessionManager: ✅ Session tokens saved to Keychain successfully")
        
        if let userTenants = user.tenants, let tenantsData = try? JSONEncoder().encode(userTenants) {
            UserDefaults.standard.set(tenantsData, forKey: tenantsKey)
        }
        
        await MainActor.run {
            self.token = newToken
            self.tenants = user.tenants
            self.user = user // Set the user property
            self.cacheUser(user)
            // Fetch permissions after login only if tenant is already selected
            if let tenantId = user.tenantId, tenantId != 0 {
                self.isLoadingPermissions = true
                Task {
                    do {
                        try await self.fetchUserDetails()
                    } catch {
                        print("SessionManager: ❌ Failed to fetch permissions after login: \(error)")
                        await MainActor.run {
                            self.isLoadingPermissions = false
                            self.errorMessage = "Failed to load user permissions. Please try logging in again."
                            // Don't logout immediately, let user see the error and retry
                        }
                    }
                }
            } else {
                // Will fetch after tenant selection
                self.isLoadingPermissions = false
            }
            
            if let userTenants = user.tenants, !userTenants.isEmpty {
                // Check for previously saved tenant first
                let savedTenantId = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int

                print("SessionManager: 🔍 Login - Saved tenant ID: \(savedTenantId ?? -1), Available tenants: \(userTenants.count)")

                // If we have a saved tenant ID and it exists in available tenants, select it
                if let savedTenantId = savedTenantId,
                   userTenants.contains(where: { ($0.tenant?.id ?? $0.tenantId) == savedTenantId }) {
                    print("SessionManager: ✅ Selecting previously saved tenant \(savedTenantId) during login")
                    Task {
                        do {
                            let (updatedToken, updatedRefresh, selectedUser) = try await APIClient.selectTenant(token: newToken, tenantId: savedTenantId)
                            await MainActor.run {
                                if KeychainHelper.saveSessionTokens(accessToken: updatedToken, refreshToken: updatedRefresh) {
                                    self.token = updatedToken
                                } else {
                                    self.errorMessage = "Failed to update session. Please try again."
                                    self.logout()
                                    return
                                }
                                UserDefaults.standard.set(savedTenantId, forKey: "selectedTenantId")
                                self.selectedTenantId = savedTenantId
                                self.isSelectingTenant = false
                                self.errorMessage = nil
                                // Preserve existing permissions when updating user after tenant selection
                                let updatedUser = User(
                                    id: selectedUser.id,
                                    firstName: selectedUser.firstName,
                                    lastName: selectedUser.lastName,
                                    email: selectedUser.email,
                                    tenantId: selectedUser.tenantId,
                                    companyId: selectedUser.companyId,
                                    company: selectedUser.company,
                                    roles: selectedUser.roles ?? self.user?.roles,
                                    permissions: selectedUser.permissions ?? self.user?.permissions,
                                    projectPermissions: selectedUser.projectPermissions ?? self.user?.projectPermissions,
                                    isSubscriptionOwner: selectedUser.isSubscriptionOwner,
                                    assignedProjects: selectedUser.assignedProjects ?? self.user?.assignedProjects,
                                    assignedSubcontractOrders: selectedUser.assignedSubcontractOrders ?? self.user?.assignedSubcontractOrders,
                                    blocked: selectedUser.blocked,
                                    createdAt: selectedUser.createdAt,
                                    userRoles: selectedUser.userRoles ?? self.user?.userRoles,
                                    userPermissions: selectedUser.userPermissions ?? self.user?.userPermissions,
                                    tenants: selectedUser.tenants ?? self.user?.tenants
                                )
                                self.user = updatedUser
                                self.cacheUser(updatedUser)
                                print("SessionManager: ✅ Successfully selected saved tenant \(savedTenantId) during login")
                            }
                        } catch {
                            await MainActor.run {
                                print("SessionManager: ❌ Saved tenant selection failed during login: \(error.localizedDescription)")
                                self.errorMessage = "Failed to select organization: \(error.localizedDescription)"
                                self.isSelectingTenant = true
                            }
                        }
                    }
                } else if userTenants.count == 1, let firstUserTenant = userTenants.first, let tenant = firstUserTenant.tenant {
                    let tenantIdToSelect = tenant.id
                    print("SessionManager: ✅ Auto-selecting single tenant ID: \(tenantIdToSelect)")
                    Task {
                        do {
                            let (updatedToken, updatedRefresh, selectedUser) = try await APIClient.selectTenant(token: newToken, tenantId: tenantIdToSelect)
                            await MainActor.run {
                                if KeychainHelper.saveSessionTokens(accessToken: updatedToken, refreshToken: updatedRefresh) {
                                    self.token = updatedToken
                                } else {
                                    self.errorMessage = "Failed to update session. Please try again."
                                    self.logout()
                                    return
                                }
                                UserDefaults.standard.set(tenantIdToSelect, forKey: "selectedTenantId")
                                self.selectedTenantId = tenantIdToSelect
                                self.isSelectingTenant = false
                                self.errorMessage = nil
                                // Preserve existing permissions when updating user after tenant selection
                                let updatedUser = User(
                                    id: selectedUser.id,
                                    firstName: selectedUser.firstName,
                                    lastName: selectedUser.lastName,
                                    email: selectedUser.email,
                                    tenantId: selectedUser.tenantId,
                                    companyId: selectedUser.companyId,
                                    company: selectedUser.company,
                                    roles: selectedUser.roles ?? self.user?.roles,
                                    permissions: selectedUser.permissions ?? self.user?.permissions,
                                    projectPermissions: selectedUser.projectPermissions ?? self.user?.projectPermissions,
                                    isSubscriptionOwner: selectedUser.isSubscriptionOwner,
                                    assignedProjects: selectedUser.assignedProjects ?? self.user?.assignedProjects,
                                    assignedSubcontractOrders: selectedUser.assignedSubcontractOrders ?? self.user?.assignedSubcontractOrders,
                                    blocked: selectedUser.blocked,
                                    createdAt: selectedUser.createdAt,
                                    userRoles: selectedUser.userRoles ?? self.user?.userRoles,
                                    userPermissions: selectedUser.userPermissions ?? self.user?.userPermissions,
                                    tenants: selectedUser.tenants ?? self.user?.tenants
                                )
                                self.user = updatedUser
                                self.cacheUser(updatedUser)
                                print("SessionManager: ✅ Successfully auto-selected single tenant \(tenantIdToSelect)")
                            }
                        } catch {
                            await MainActor.run {
                                print("SessionManager: ❌ Auto-select tenant failed: \(error.localizedDescription)")
                                self.errorMessage = "Failed to select organization: \(error.localizedDescription)"
                                self.isSelectingTenant = true
                            }
                        }
                    }
                } else {
                    print("SessionManager: 📋 Multiple tenants (\(userTenants.count)) found, showing tenant selection screen")
                    self.isSelectingTenant = true
                    self.errorMessage = nil
                }
            } else {
                print("SessionManager: ❌ No tenants found for user \(user.email ?? "N/A")")
                self.errorMessage = "No organizations found for your account. Please contact support."
                self.isSelectingTenant = true
            }
        }
    }
    
    // Called by LoginView right after a successful manual (password) login.
    // Always remembers the email for prefilling. If Face ID is already enabled, refreshes
    // the stored password. Otherwise offers to enable Face ID when biometrics are available
    // and the user hasn't previously dismissed the offer on this device.
    @MainActor
    func noteSuccessfulPasswordLogin(email: String, password: String) {
        _ = KeychainHelper.saveEmail(email)

        if KeychainHelper.hasStoredPassword() {
            _ = KeychainHelper.savePassword(password)
            return
        }

        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        guard !UserDefaults.standard.bool(forKey: faceIDEnrollmentDismissedKey) else { return }

        pendingFaceIDEmail = email
        pendingFaceIDPassword = password
        shouldOfferFaceIDEnrollment = true
    }

    // User tapped "Enable" on the Face ID enrollment prompt.
    func enableFaceIDFromPendingCredentials() {
        defer { clearPendingFaceIDEnrollment() }
        guard let email = pendingFaceIDEmail, let password = pendingFaceIDPassword else { return }
        if !KeychainHelper.enableFaceIDCredentials(email: email, password: password) {
            print("SessionManager: ❌ Failed to enable Face ID from post-login prompt - user can retry from Settings")
        }
    }

    // User tapped "Not Now" (or dismissed) the Face ID enrollment prompt. Remember that,
    // so we don't nag on every subsequent login — they can still enable it later from
    // Settings.
    func dismissFaceIDEnrollmentPrompt() {
        UserDefaults.standard.set(true, forKey: faceIDEnrollmentDismissedKey)
        clearPendingFaceIDEnrollment()
    }

    private func clearPendingFaceIDEnrollment() {
        pendingFaceIDEmail = nil
        pendingFaceIDPassword = nil
        shouldOfferFaceIDEnrollment = false
    }

    func getCachedTenants() -> [User.UserTenant]? {
        if let tenantsData = UserDefaults.standard.data(forKey: tenantsKey),
           let tenants = try? JSONDecoder().decode([User.UserTenant].self, from: tenantsData) {
            return tenants
        }
        return nil
    }

    func selectTenant(token: String, tenantId: Int) async throws {
        if await NetworkMonitor.shared.isNetworkAvailable() {
            let (newToken, refreshToken, user) = try await APIClient.selectTenant(token: token, tenantId: tenantId)
            print("SessionManager: Tenant selected with token=\(newToken.prefix(10))..., user=\(user.email ?? "N/A")")
            
            guard KeychainHelper.saveSessionTokens(accessToken: newToken, refreshToken: refreshToken) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save session after tenant selection"])
            }
            
            let selectedTenantId = user.tenantId ?? 0
            guard selectedTenantId != 0 else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to confirm organization selection"])
            }
            
            await MainActor.run {
                self.token = newToken
                UserDefaults.standard.set(selectedTenantId, forKey: "selectedTenantId")
                self.selectedTenantId = selectedTenantId
                self.isSelectingTenant = false
                self.errorMessage = nil
                // Preserve existing permissions when updating user after tenant selection
                let updatedUser = User(
                    id: user.id,
                    firstName: user.firstName,
                    lastName: user.lastName,
                    email: user.email,
                    tenantId: user.tenantId,
                    companyId: user.companyId,
                    company: user.company,
                    roles: user.roles ?? self.user?.roles,
                    permissions: user.permissions ?? self.user?.permissions,
                    projectPermissions: user.projectPermissions ?? self.user?.projectPermissions,
                    isSubscriptionOwner: user.isSubscriptionOwner,
                    assignedProjects: user.assignedProjects ?? self.user?.assignedProjects,
                    assignedSubcontractOrders: user.assignedSubcontractOrders ?? self.user?.assignedSubcontractOrders,
                    blocked: user.blocked,
                    createdAt: user.createdAt,
                    userRoles: user.userRoles ?? self.user?.userRoles,
                    userPermissions: user.userPermissions ?? self.user?.userPermissions,
                    tenants: user.tenants ?? self.user?.tenants
                )
                self.user = updatedUser
                self.cacheUser(updatedUser)
                // Fetch permissions after tenant selection
                self.isLoadingPermissions = true
                Task {
                    do {
                        try await self.fetchUserDetails()
                    } catch {
                        print("SessionManager: ❌ Failed to fetch permissions after tenant selection: \(error)")
                        await MainActor.run {
                            self.isLoadingPermissions = false
                        }
                    }
                }
            }
        } else {
            // Offline tenant selection
            if let cachedTenants = getCachedTenants(), cachedTenants.contains(where: { $0.tenant?.id == tenantId }) {
                await MainActor.run {
                    self.token = token
                    UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                    self.selectedTenantId = tenantId
                    self.isSelectingTenant = false
                    self.errorMessage = nil
                    // Note: The user object is not updated in offline mode.
                    // The app will continue using the previously cached user data.
                }
            } else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Selected organization not found in cached data"])
            }
        }
    }
    
    // `clearSavedCredentials` distinguishes a user-initiated Sign Out (which should fully
    // sign the device out, including the saved email/password used for Face ID and silent
    // re-auth) from internal session-refresh logouts, e.g. `handleTokenExpiration()` after a
    // failed silent re-auth, where we intentionally keep the saved credentials around so the
    // user can still sign back in with Face ID rather than typing their password again.
    func logout(clearSavedCredentials: Bool = false) {
        print("SessionManager: Logging out (clearSavedCredentials: \(clearSavedCredentials))")
        
        // Track logout event before clearing user data
        AnalyticsManager.shared.trackLogout()
        AnalyticsManager.shared.setUserId(nil)
        AnalyticsManager.shared.setTenantId(nil)
        AnalyticsService.shared.clearAuthToken()

        _ = KeychainHelper.deleteSessionTokens()
        if clearSavedCredentials {
            _ = KeychainHelper.deleteCredentials()
            // Give the user a fresh chance to be offered Face ID enrollment next time
            // they sign in, since they explicitly signed all the way out.
            UserDefaults.standard.removeObject(forKey: faceIDEnrollmentDismissedKey)
            UserDefaults.standard.removeObject(forKey: "selectedTenantId")
            UserDefaults.standard.removeObject(forKey: tenantsKey)
            clearCachedUser()
            self.selectedTenantId = nil
            self.tenants = nil
            self.user = nil
        }
        clearPendingFaceIDEnrollment()
        // Soft logout (session expiry) keeps saved email/password for Face ID unlock,
        // and clears only access + refresh tokens above.
        self.token = nil
        self.isSelectingTenant = false
        self.errorMessage = nil
        self.isLoadingPermissions = false
        self.isReauthInProgress = false
        // Force LoginView to remount so text fields / focus / loading state aren't stuck
        // from the previous session (common after signing out from the profile sidebar).
        self.loginFormID &+= 1
    }

    func handleTokenExpiration() {
        print("SessionManager: Token expired, attempting silent re-login")
        if isReauthInProgress { return }
        Task {
            await MainActor.run { self.isReauthInProgress = true }
            defer { Task { @MainActor in self.isReauthInProgress = false } }
            if await self.attemptSilentReauth() {
                await MainActor.run { self.errorMessage = nil }
            } else {
                await MainActor.run {
                    self.errorMessage = "Session expired. Please log in again."
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.logout()
                }
            }
        }
    }

    func hasPermission(_ permissionName: String) -> Bool {
        guard let permissions = user?.permissions else {
            return false
        }
        return permissions.contains { $0.name == permissionName }
    }
    
    // Check if user is properly authenticated (has permissions loaded)
    var isProperlyAuthenticated: Bool {
        guard let user = user else { return false }
        guard let permissions = user.permissions, !permissions.isEmpty else { return false }
        return !isLoadingPermissions
    }

    private func cacheUser(_ user: User) {
        if let userData = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(userData, forKey: userKey)
        }
    }

    private func getCachedUser() -> User? {
        if let userData = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(User.self, from: userData) {
            return user
        }
        return nil
    }

    private func fetchUserDetails() async throws {
        guard let token = token else {
            print("SessionManager: fetchUserDetails - ❌ No token available")
            throw NSError(domain: "SessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No token available"])
        }

        // Ensure we have a tenant selected before hitting the backend
        let effectiveTenantId = selectedTenantId ?? user?.tenantId ?? 0
        if effectiveTenantId == 0 {
            print("SessionManager: fetchUserDetails - ⛔️ Skipping: no tenant selected yet (will fetch after tenant selection)")
            await MainActor.run { self.isLoadingPermissions = false }
            return
        }

        print("SessionManager: fetchUserDetails - ✅ Token available, length: \(token.count)")
        print("SessionManager: Fetching user details with token: \(token.prefix(10))...")

        // Set loading state
        await MainActor.run {
            self.isLoadingPermissions = true
        }

        // Retry logic for fetching user details
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let userDetails = try await APIClient.fetchUserDetails(token: token)
                print("SessionManager: ✅ Fetched user details successfully (attempt \(attempt))")
                print("SessionManager: Fetched permissions count: \(userDetails.permissions.count)")
                print("SessionManager: Fetched roles count: \(userDetails.roles.count)")

                // Check if we got empty permissions - this indicates a backend issue
                if userDetails.permissions.isEmpty && userDetails.roles.isEmpty {
                    print("SessionManager: ⚠️ Backend returned empty permissions/roles - this is a backend issue!")
                    print("SessionManager: ⚠️ User will have no permissions until backend is fixed")
                    
                    // TEMPORARY WORKAROUND: Check if this is an admin account that should have permissions
                    // We can detect this by checking if the user has multiple tenants (admin accounts typically do)
                    if let currentUser = user, let tenants = currentUser.tenants, tenants.count > 1 {
                        print("SessionManager: 🔧 Detected admin account with empty permissions - this needs backend fix")
                        print("SessionManager: 🔧 Admin account should have permissions but backend is not returning them")
                    }
                }

                // Create a new User instance with updated details
                await MainActor.run {
                    if let currentUser = user {
                        let updatedUser = User(
                            id: currentUser.id,
                            firstName: currentUser.firstName,
                            lastName: currentUser.lastName,
                            email: currentUser.email,
                            tenantId: currentUser.tenantId,
                            companyId: currentUser.companyId,
                            company: currentUser.company,
                            roles: userDetails.roles,
                            permissions: userDetails.permissions,
                            projectPermissions: currentUser.projectPermissions,
                            isSubscriptionOwner: userDetails.isSubscriptionOwner,
                            assignedProjects: currentUser.assignedProjects,
                            assignedSubcontractOrders: currentUser.assignedSubcontractOrders,
                            blocked: currentUser.blocked,
                            createdAt: currentUser.createdAt,
                            userRoles: currentUser.userRoles,
                            userPermissions: currentUser.userPermissions,
                            tenants: userDetails.tenants
                        )

                        self.user = updatedUser
                        self.cacheUser(updatedUser)
                        print("SessionManager: ✅ User details updated and cached")
                    }
                }

                // Clear loading state on success
                await MainActor.run {
                    self.isLoadingPermissions = false
                }
                return // Success, exit the retry loop

            } catch {
                lastError = error
                print("SessionManager: ❌ Failed to fetch user details (attempt \(attempt)/3): \(error)")

                // Don't retry on authentication errors
                if let apiError = error as? APIError {
                    switch apiError {
                    case .tokenExpired, .forbidden:
                        print("SessionManager: ❌ Authentication error, not retrying")
                        throw error
                    case .invalidResponse(let status) where status == 409:
                        // Tenant not selected yet — treat as non-fatal and wait for tenant selection
                        print("SessionManager: ℹ️ Received 409 (tenant not selected). Will stop retries and wait for tenant selection.")
                        await MainActor.run { self.isLoadingPermissions = false }
                        return
                    default:
                        break
                    }
                }

                // Wait before retrying (exponential backoff)
                if attempt < 3 {
                    let delay = Double(attempt) * 1.0 // 1s, 2s, 3s
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // If we get here, all retries failed
        print("SessionManager: ❌ All retry attempts failed. Last error: \(lastError?.localizedDescription ?? "Unknown")")

        // Clear loading state on failure
        await MainActor.run {
            self.isLoadingPermissions = false
        }

        // Try to get token from Keychain directly to verify it's accessible
        if let keychainToken = KeychainHelper.getToken() {
            print("SessionManager: Token is accessible from Keychain, length: \(keychainToken.count)")
        } else {
            print("SessionManager: ❌ Token NOT accessible from Keychain!")
        }

        throw lastError ?? NSError(domain: "SessionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user details after retries"])
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: userKey)
    }
}
