import Foundation
import Security
import SpruceCore

/// The user's VirusTotal API key, kept only in the macOS Keychain as a generic password
/// (service "app.spruce.virustotal", account "api-key"). It is never written to settings,
/// user defaults, logs or any file, and never printed. The calls can block (the Keychain
/// may ask the user to allow access), so make them off the main thread.
enum ProtectionVirusTotalKeychain {
    static let service = "app.spruce.virustotal"
    static let account = "api-key"

    /// A Keychain call that failed, with its status code (never the key).
    struct Failure: Error, CustomStringConvertible {
        let status: OSStatus

        var description: String {
            "Spruce couldn't save the key in your keychain (error \(status))."
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves the key, replacing an older one.
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        var status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "Spruce: VirusTotal API key"
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    /// The saved key, or nil when there is none (or the Keychain refused access).
    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// True when a key is saved. Reads only the item's attributes, not the key, so it never
    /// asks the user for Keychain access.
    static func exists() -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// Removes the key. True when it's gone (or there was none).
    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
