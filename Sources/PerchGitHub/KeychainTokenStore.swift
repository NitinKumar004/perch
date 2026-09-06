import Foundation
import Security

/// The production token store: the GitHub token, JSON-encoded, in the macOS
/// Keychain. Marked device-only + available after first unlock, so it never
/// syncs to iCloud and never leaves this Mac.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.perch.github", account: String = "user-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> GitHubToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw GitHubAuthError.keychain(status: status)
        }
        guard let token = try? JSONDecoder().decode(GitHubToken.self, from: data) else {
            throw GitHubAuthError.decoding
        }
        return token
    }

    public func save(_ token: GitHubToken) throws {
        let data = try JSONEncoder().encode(token)

        // Single-touch write: try to add; if it already exists, update in place.
        // (The old delete-then-add touched the keychain twice, which could
        // trigger two authorization prompts.)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecSuccess { return }

        if addStatus == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw GitHubAuthError.keychain(status: updateStatus) }
            return
        }
        throw GitHubAuthError.keychain(status: addStatus)
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status: status)
        }
    }
}
