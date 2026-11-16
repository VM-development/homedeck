import Foundation
import Security

/// Device secrets (bind keys, tokens) live in the iPhone Keychain only: never in files, UserDefaults or the log.
/// Readable after the first unlock, so background Bluetooth work can use them while the phone is locked.
public enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "HomeDeck",
         kSecAttrAccount as String: account]
    }

    public static func get(_ account: String) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nil deletes.
    public static func set(_ value: String?, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value else { return }
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
