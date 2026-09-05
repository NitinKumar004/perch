import Foundation

/// Where the GitHub token lives. Abstracted so the auth layer can be tested with
/// an in-memory store and run for real against the Keychain.
public protocol TokenStore: Sendable {
    func load() throws -> GitHubToken?
    func save(_ token: GitHubToken) throws
    func clear() throws
}

/// A process-lifetime store for tests and previews. Never used in production.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: GitHubToken?

    public init(_ initial: GitHubToken? = nil) {
        token = initial
    }

    public func load() throws -> GitHubToken? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func save(_ token: GitHubToken) throws {
        lock.lock(); self.token = token; lock.unlock()
    }

    public func clear() throws {
        lock.lock(); token = nil; lock.unlock()
    }
}
