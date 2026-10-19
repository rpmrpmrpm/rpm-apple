import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(_ key: String) async -> Data?
    func write(_ key: String, _ value: Data) async
    func delete(_ key: String) async
}

/// Keeps the session in the Keychain, not in a file in the app container.
///
/// A file in the container can be read from an unencrypted backup, and a refresh
/// token is a long-lived credential.
///
/// `AfterFirstUnlock` is used instead of `WhenUnlocked`. Playback continues in the
/// background with the phone locked, and a stream URL has to be re-signed during
/// playback. With `WhenUnlocked`, the music would stop at the first token refresh
/// after the screen went dark.
public struct Keychain: SecretStore {
    private let service: String

    public init(service: String = "com.rpm.player") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    public func read(_ key: String) async -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    public func write(_ key: String, _ value: Data) async {
        // Delete first, then add. `SecItemUpdate` fails when the item does not exist yet.
        // Deleting first gives one code path instead of two.
        await delete(key)

        var q = query(key)
        q[kSecValueData as String] = value
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    public func delete(_ key: String) async {
        SecItemDelete(query(key) as CFDictionary)
    }
}
