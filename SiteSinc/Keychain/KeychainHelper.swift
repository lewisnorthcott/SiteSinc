import Foundation
import Security
import LocalAuthentication

struct KeychainHelper {

    static let service = Bundle.main.bundleIdentifier ?? "com.example.default" // Use your app's bundle ID
    private static let tokenAccount = "authToken"
    private static let refreshTokenAccount = "refreshToken"
    private static let emailAccount = "userEmail"
    private static let passwordAccount = "userPassword"

    // MARK: - Token

    // Save Token
    static func saveToken(_ token: String) -> Bool {
        print("KeychainHelper: Saving token with service: \(service)")
        return saveString(token, account: tokenAccount, label: "token")
    }

    // Get Token
    static func getToken() -> String? {
        print("KeychainHelper: Getting token with service: \(service)")
        return getString(account: tokenAccount, label: "token")
    }

    // Delete Token
    static func deleteToken() -> Bool {
        return deleteAccount(tokenAccount)
    }

    // MARK: - Refresh Token

    static func saveRefreshToken(_ refreshToken: String) -> Bool {
        return saveString(refreshToken, account: refreshTokenAccount, label: "refreshToken")
    }

    static func getRefreshToken() -> String? {
        return getString(account: refreshTokenAccount, label: "refreshToken")
    }

    static func deleteRefreshToken() -> Bool {
        return deleteAccount(refreshTokenAccount)
    }

    /// Saves access + refresh together. Refresh is optional so older API payloads still work.
    static func saveSessionTokens(accessToken: String, refreshToken: String?) -> Bool {
        let accessSaved = saveToken(accessToken)
        if let refreshToken, !refreshToken.isEmpty {
            let refreshSaved = saveRefreshToken(refreshToken)
            return accessSaved && refreshSaved
        }
        return accessSaved
    }

    /// Clears both access and refresh tokens (soft logout / session expiry).
    static func deleteSessionTokens() -> Bool {
        let accessDeleted = deleteToken()
        let refreshDeleted = deleteRefreshToken()
        return accessDeleted && refreshDeleted
    }

    // MARK: - Private Keychain helpers

    private static func saveString(_ value: String, account: String, label: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            print("KeychainHelper: Failed to convert \(label) to data")
            return false
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let addQuery = baseQuery.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }

        SecItemDelete(baseQuery as CFDictionary)
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        print("KeychainHelper: Save \(label) status: \(status)")
        return status == errSecSuccess
    }

    private static func getString(account: String, label: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            let value = String(data: retrievedData, encoding: .utf8)
            print("KeychainHelper: ✅ Retrieved \(label) successfully, length: \(value?.count ?? 0)")
            return value
        } else {
            if status == errSecItemNotFound {
                print("KeychainHelper: ℹ️  \(label) not found in Keychain")
            } else if status == errSecInteractionNotAllowed {
                print("KeychainHelper: 🚫 Keychain interaction not allowed for \(label) (device locked?)")
            } else {
                print("KeychainHelper: ❌ Failed to get \(label) - Status: \(status)")
            }
            return nil
        }
    }

    private static func deleteAccount(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Email

    // Save Email
    static func saveEmail(_ email: String) -> Bool {
        guard let data = email.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: emailAccount
        ]
        let addQuery = baseQuery.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }

        // Delete any existing item first
        SecItemDelete(baseQuery as CFDictionary)

        // Add the new item
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // Get Email
    static func getEmail() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: emailAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        } else {
            if status != errSecItemNotFound {
                print("Keychain read error for email: \(status)")
            }
            return nil
        }
    }

    // MARK: - Password
    //
    // Stored with device-only accessibility (not synced to iCloud, not readable while
    // locked). Face ID is enforced at the UI layer before reading — not via a biometric
    // SecAccessControl ACL. Biometry-gated Keychain items break silent session refresh
    // (any background read either ambushes the user with Face ID or always fails), which
    // caused sessions to drop and Face ID login to fail after the earlier hardening.

    // Save Password
    static func savePassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount
        ]
        let addQuery = baseQuery.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }

        // Delete any existing item first (also clears any older biometry-gated item)
        SecItemDelete(baseQuery as CFDictionary)

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("KeychainHelper: ❌ Failed to save password - status: \(status)")
        }
        return status == errSecSuccess
    }

    // Get Password. The optional LAContext parameter is retained for call-site
    // compatibility; it is unused now that the item is not biometry-ACL gated.
    static func getPassword(context: LAContext? = nil) -> String? {
        _ = context
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        } else {
            if status != errSecItemNotFound {
                print("Keychain read error for password: \(status)")
            }
            return nil
        }
    }

    // Whether a password has been saved for Face ID / silent re-auth.
    static func hasStoredPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: kCFBooleanFalse!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    // Saves both credentials needed for Face ID sign-in and verifies the write took effect.
    static func enableFaceIDCredentials(email: String, password: String) -> Bool {
        let emailSaved = saveEmail(email)
        let passwordSaved = savePassword(password)
        guard emailSaved, passwordSaved, hasStoredPassword() else {
            print("KeychainHelper: ❌ Failed to enable Face ID credentials (email saved: \(emailSaved), password saved: \(passwordSaved))")
            return false
        }
        return true
    }

    // Optional: Delete Email and Password (e.g., on logout)
    static func deleteCredentials() -> Bool {
        let emailQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: emailAccount
        ]
        
        let passwordQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount
        ]
        
        let emailStatus = SecItemDelete(emailQuery as CFDictionary)
        let passwordStatus = SecItemDelete(passwordQuery as CFDictionary)
        
        return (emailStatus == errSecSuccess || emailStatus == errSecItemNotFound) &&
               (passwordStatus == errSecSuccess || passwordStatus == errSecItemNotFound)
    }
}
