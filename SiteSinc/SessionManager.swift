//
//  SessionManager.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 25/05/2025.
//

import SwiftUI

class SessionManager: ObservableObject {
    @Published var token: String? = KeychainHelper.getToken()
    @Published var selectedTenantId: Int? = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int
    @Published var tenants: [User.UserTenant]?
    @Published var errorMessage: String?
    @Published var isSelectingTenant: Bool = false
    @Published var user: User?

    private let tenantsKey = "cachedTeanants"
    private let userKey = "cachedUser"

    init() {
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

        // If we have a cached user but no permissions, try to fetch them
        if let cachedUser = user, (cachedUser.permissions?.isEmpty ?? true), keychainToken != nil {
            print("SessionManager: ⚠️  Cached user has no permissions, attempting to fetch now")
            Task { try? await self.fetchUserDetails() }
        }
    }
    
    // Validate the current token with backend; if invalid, attempt silent re-login.
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

    // Try to silently re-authenticate using saved credentials and restore previous tenant if possible.
    func attemptSilentReauth() async -> Bool {
        guard let email = KeychainHelper.getEmail(),
              let password = KeychainHelper.getPassword() else {
            print("SessionManager: ❌ Silent re-auth failed - no saved credentials")
            return false
        }
        do {
            let (newToken, user) = try await APIClient.login(email: email, password: password)
            guard KeychainHelper.saveToken(newToken) else {
                print("SessionManager: ❌ Silent re-auth failed - could not save token")
                return false
            }
            await MainActor.run {
                self.token = newToken
                self.tenants = user.tenants
                self.user = user
                self.cacheUser(user)
            }

            // Fetch user details and ensure permissions are loaded
            do {
                try await self.fetchUserDetails()
                print("SessionManager: ✅ Silent re-auth successful with permissions")
            } catch {
                print("SessionManager: ⚠️ Silent re-auth successful but failed to fetch permissions: \(error)")
                // Don't fail the entire re-auth if permissions fetch fails
                // The user can still use the app, just without proper permissions
            }
            // Tenant selection logic for silent re-auth
            let savedTenantId = UserDefaults.standard.object(forKey: "selectedTenantId") as? Int
            let userTenants = user.tenants ?? []

            print("SessionManager: 🔍 Tenant selection - Saved tenant ID: \(savedTenantId ?? -1), Available tenants: \(userTenants.count)")

            // Debug: Log all available tenant IDs
            for (index, tenant) in userTenants.enumerated() {
                let tenantId = tenant.tenant?.id ?? tenant.tenantId ?? -1
                print("SessionManager: 🔍 Available tenant \(index): ID=\(tenantId), Name=\(tenant.tenant?.name ?? "Unknown")")
            }

            // Prefer previously selected tenant if still available
            if let savedTenantId = savedTenantId {
                let tenantExists = userTenants.contains(where: { ($0.tenant?.id ?? $0.tenantId) == savedTenantId })
                print("SessionManager: 🔍 Checking if saved tenant \(savedTenantId) exists in available tenants: \(tenantExists)")

                if tenantExists {
                    print("SessionManager: ✅ Selecting previously saved tenant \(savedTenantId)")
                    let (updatedToken, selectedUser) = try await APIClient.selectTenant(token: newToken, tenantId: savedTenantId)
                    guard KeychainHelper.saveToken(updatedToken) else {
                        print("SessionManager: ❌ Failed to save updated token after tenant selection")
                        return false
                    }
                    await MainActor.run {
                        self.token = updatedToken
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
                        print("SessionManager: ✅ Successfully selected saved tenant \(savedTenantId)")
                    }
                    return true
                } else {
                    print("SessionManager: ⚠️ Saved tenant \(savedTenantId) no longer available, will show tenant selection")
                }
            } else {
                print("SessionManager: ℹ️ No previously saved tenant ID found")
            }

            // If only one tenant, auto-select
            if userTenants.count == 1, let tenantId = userTenants.first?.tenant?.id ?? userTenants.first?.tenantId {
                print("SessionManager: ✅ Auto-selecting single available tenant \(tenantId)")
                let (updatedToken, selectedUser) = try await APIClient.selectTenant(token: newToken, tenantId: tenantId)
                guard KeychainHelper.saveToken(updatedToken) else {
                    print("SessionManager: ❌ Failed to save updated token after auto-selecting tenant")
                    return false
                }
                await MainActor.run {
                    self.token = updatedToken
                    UserDefaults.standard.set(tenantId, forKey: "selectedTenantId")
                    self.selectedTenantId = tenantId
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
                    print("SessionManager: ✅ Successfully auto-selected tenant \(tenantId)")
                }
                return true
            }

            // Multiple tenants without valid saved selection: prompt selection
            print("SessionManager: 📋 Multiple tenants (\(userTenants.count)) available, showing tenant selection screen")
            await MainActor.run {
                self.isSelectingTenant = true
                self.errorMessage = nil
            }
            return true
        } catch {
            return false
        }
    }
    
    func login(email: String, password: String) async throws {
        print("SessionManager: Starting login for email: \(email)")
        print("SessionManager: Device info - Model: \(await UIDevice.current.model), System: \(await UIDevice.current.systemName) \(await UIDevice.current.systemVersion)")
        let bundleId = Bundle.main.bundleIdentifier ?? "nil"
        print("SessionManager: Bundle identifier: \(bundleId)")

        let (newToken, user) = try await APIClient.login(email: email, password: password)
        print("SessionManager: Login successful with token=\(newToken.prefix(10))..., user=\(user.email ?? "N/A")")
        print("SessionManager: User permissions count: \(user.permissions?.count ?? 0)")
        print("SessionManager: User roles count: \(user.roles?.count ?? 0)")

        print("SessionManager: Attempting to save token to Keychain...")
        guard KeychainHelper.saveToken(newToken) else {
            print("SessionManager: ❌ Failed to save token to Keychain!")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save session"])
        }
        print("SessionManager: ✅ Token saved to Keychain successfully")
        
        if let userTenants = user.tenants, let tenantsData = try? JSONEncoder().encode(userTenants) {
            UserDefaults.standard.set(tenantsData, forKey: tenantsKey)
        }
        
        await MainActor.run {
            self.token = newToken
            self.tenants = user.tenants
            self.user = user // Set the user property
            self.cacheUser(user)
            Task { try? await self.fetchUserDetails() }
            
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
                            let (updatedToken, selectedUser) = try await APIClient.selectTenant(token: newToken, tenantId: savedTenantId)
                            await MainActor.run {
                                if KeychainHelper.saveToken(updatedToken) {
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
                            let (updatedToken, selectedUser) = try await APIClient.selectTenant(token: newToken, tenantId: tenantIdToSelect)
                            await MainActor.run {
                                if KeychainHelper.saveToken(updatedToken) {
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
    
    func getCachedTenants() -> [User.UserTenant]? {
        if let tenantsData = UserDefaults.standard.data(forKey: tenantsKey),
           let tenants = try? JSONDecoder().decode([User.UserTenant].self, from: tenantsData) {
            return tenants
        }
        return nil
    }

    func selectTenant(token: String, tenantId: Int) async throws {
        if await NetworkMonitor.shared.isNetworkAvailable() {
            let (newToken, user) = try await APIClient.selectTenant(token: token, tenantId: tenantId)
            print("SessionManager: Tenant selected with token=\(newToken.prefix(10))..., user=\(user.email ?? "N/A")")
            
            guard KeychainHelper.saveToken(newToken) else {
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
            Task { try? await self.fetchUserDetails() }
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
    
    func logout() {
        print("SessionManager: Logging out")
        _ = KeychainHelper.deleteToken()
        UserDefaults.standard.removeObject(forKey: "selectedTenantId")
        UserDefaults.standard.removeObject(forKey: "cachedTenants")
        clearCachedUser()
        self.token = nil
        self.selectedTenantId = nil
        self.tenants = nil
        self.user = nil // Clear user on logout
        self.isSelectingTenant = false
        self.errorMessage = nil
    }

    func handleTokenExpiration() {
        print("SessionManager: Token expired, attempting silent re-login")
        Task {
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

        print("SessionManager: fetchUserDetails - ✅ Token available, length: \(token.count)")
        print("SessionManager: Fetching user details with token: \(token.prefix(10))...")

        // Retry logic for fetching user details
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let userDetails = try await APIClient.fetchUserDetails(token: token)
                print("SessionManager: ✅ Fetched user details successfully (attempt \(attempt))")
                print("SessionManager: Fetched permissions count: \(userDetails.permissions.count)")
                print("SessionManager: Fetched roles count: \(userDetails.roles.count)")

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
