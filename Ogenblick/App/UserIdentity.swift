import Foundation
import Security

/// Provides a stable anonymous user ID that persists across app reinstalls via Keychain.
/// This ID is used for analytics, crash reports, and will later serve as the seed for
/// a Firebase Auth account when social features are added.
final class UserIdentity {

    static let shared = UserIdentity()

    /// The stable anonymous user ID (UUID string). Created on first access, stored in Keychain.
    let id: String

    private static let service = "com.ogenblick.user-identity"
    private static let account = "anonymous-user-id"

    private init() {
        if let existing = Self.readFromKeychain() {
            id = existing
        } else {
            let newID = UUID().uuidString
            Self.writeToKeychain(newID)
            id = newID
        }
    }

    // MARK: - Keychain helpers

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private static func writeToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
