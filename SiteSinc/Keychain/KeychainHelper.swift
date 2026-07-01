import Foundation
import Security
import LocalAuthentication

struct KeychainHelper {

    static let service = Bundle.main.bundleIdentifier ?? "com.example.default" // Use your app's bundle ID
    private static let tokenAccount = "authToken"
    private static let emailAccount = "userEmail"
    private static let passwordAccount = "userPassword"

    // MARK: - Token

    // Save Token
    static func saveToken(_ token: String) -> Bool {
        print("KeychainHelper: Saving token with service: \(service)")
        guard let data = token.data(using: .utf8) else {
            print("KeychainHelper: Failed to convert token to data")
            return false
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
        ]
        let addQuery = baseQuery.merging([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }

        // Delete any existing item first
        SecItemDelete(baseQuery as CFDictionary)

        // Add the new item
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        print("KeychainHelper: Save token status: \(status)")
        return status == errSecSuccess
    }

    // Get Token
    static func getToken() -> String? {
        print("KeychainHelper: Getting token with service: \(service)")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        print("KeychainHelper: Get token status: \(status)")

        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            let token = String(data: retrievedData, encoding: .utf8)
            print("KeychainHelper: ✅ Retrieved token successfully, length: \(token?.count ?? 0)")
            return token
        } else {
            print("KeychainHelper: ❌ Failed to get token - Status: \(status)")
            if status == errSecItemNotFound {
                print("KeychainHelper: ℹ️  Token not found in Keychain")
            } else if status == errSecInteractionNotAllowed {
                print("KeychainHelper: 🚫 Keychain interaction not allowed (device locked?)")
            } else {
                print("KeychainHelper: ⚠️  Other Keychain error: \(status)")
            }
            return nil
        }
    }

    // Delete Token
    static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount
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

    // MARK: - Password (biometric-gated)
    //
    // The password item is protected with a SecAccessControl requiring the current
    // biometric set (Face ID / Touch ID). The OS enforces this at read time, so any
    // code path that calls getPassword() will be gated by biometrics — not just the
    // manual LAContext check the UI layer performs before calling it. Callers that
    // want a custom prompt reason should pre-evaluate an LAContext via
    // `evaluatePolicy(_:localizedReason:)` and pass that same context in, so the
    // Keychain read reuses the already-succeeded authentication instead of prompting
    // a second time.

    // Save Password
    static func savePassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessControlError
        ) else {
            print("KeychainHelper: ❌ Failed to create access control for password: \(String(describing: accessControlError?.takeRetainedValue()))")
            return false
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount
        ]
        let addQuery = baseQuery.merging([
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: data
        ]) { _, new in new }

        // Delete any existing item first (deletion does not require biometric auth)
        SecItemDelete(baseQuery as CFDictionary)

        // Add the new item
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // Get Password. Pass a pre-authenticated LAContext to avoid a duplicate biometric
    // prompt when the caller already ran evaluatePolicy() with its own reason text.
    static func getPassword(context: LAContext? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        } else {
            switch status {
            case errSecItemNotFound, errSecUserCanceled, errSecAuthFailed:
                break // Expected outcomes (no saved credentials, or biometric auth declined/failed)
            default:
                print("Keychain read error for password: \(status)")
            }
            return nil
        }
    }

    // Whether a biometric-gated password has been saved (without triggering a prompt).
    // Uses kSecReturnData = false so this check never invokes Face ID/Touch ID itself.
    static func hasStoredPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: kCFBooleanFalse!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
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
