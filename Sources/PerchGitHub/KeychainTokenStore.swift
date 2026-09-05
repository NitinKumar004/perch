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
        // Atomic replace: remove any existing item, then add the fresh one.
        SecItemDelete(baseQuery as CFDictionary)

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw GitHubAuthError.keychain(status: status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status: status)
        }
    }
}
