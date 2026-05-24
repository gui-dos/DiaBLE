import Foundation
import Security

/// Persistent store for the 149-byte `kAuth` blob the SKB returns from
/// op 9 (`exportKAuth`). Keyed by a sensor identifier (the BLE MAC from
/// the NFC takeover response).
///
/// `keychain` uses iOS Keychain (`kSecClassGenericPassword`). The blob
/// is encrypted at rest by the system and only accessible to this app.
/// For tests / SwiftUI previews use `inMemory`.
struct Libre3KAuthStore {
    let load: (String) -> Data?
    let save: (String, Data) -> Bool
    let remove: (String) -> Bool

    // MARK: - Keychain backend

    static let keychain = Libre3KAuthStore(
        load: { id in keychainRead(account: id) },
        save: { id, blob in keychainWrite(account: id, value: blob) },
        remove: { id in keychainDelete(account: id) }
    )

    // MARK: - In-memory backend (tests / previews)

    static func inMemory() -> Libre3KAuthStore {
        final class Box { var map: [String: Data] = [:] }
        let box = Box()
        return Libre3KAuthStore(
            load: { box.map[$0] },
            save: { id, blob in box.map[id] = blob; return true },
            remove: { id in box.map.removeValue(forKey: id) != nil }
        )
    }

    // MARK: - Keychain primitives

    private static let service = "dev.libre3andriodserver.kauth"

    private static func keychainRead(account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecReturnData as String:  true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        _ = query  // silence unused-var warning for swift 6
        return data
    }

    private static func keychainWrite(account: String, value: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String:    value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var add = query
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func keychainDelete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
