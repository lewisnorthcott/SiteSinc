import Foundation
import Security

struct KeychainHelper {

    static let service = Bundle.main.bundleIdentifier ?? "com.example.default" // Use your app's bundle ID
    private static let tokenAccount = "authToken"
    private static let emailAccount = "userEmail"
    private static let passwordAccount = "userPassword"

    // Save Token
    static func saveToken(_ token: String) -> Bool {
        print("KeychainHelper: Saving token with service: \(service)")
        guard let data = token.data(using: .utf8) else {
            print("KeychainHelper: Failed to convert token to data")
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
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

    // Save Email
    static func saveEmail(_ email: String) -> Bool {
        guard let data = email.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: emailAccount,
            kSecValueData as String: data
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
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

    // Save Password
    static func savePassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecValueData as String: data
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // Get Password
    static func getPassword() -> String? {
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
