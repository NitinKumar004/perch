import Foundation
import PerchCore

/// The one thing the rest of the app talks to for GitHub auth. It owns the
/// token: it hands out a *valid* access token (refreshing silently when one is
/// about to expire) and runs the device-login handshake. Everything above it
/// just asks for a token and never thinks about expiry.
///
/// An `actor`, so concurrent callers can't race the token refresh.
public actor GitHubAuth {
    private let flow: GitHubDeviceFlow
    private let store: any TokenStore
    private let clock: any Clock
    private let refreshBuffer: TimeInterval

    /// In-memory copy of the token so the Keychain is read at most once per
    /// launch. Every poll asks for a token; without this cache each ask would
    /// re-read the Keychain and re-trigger the OS access prompt. `loaded` guards
    /// against caching a `nil` and re-hitting the Keychain forever.
    private var cachedToken: GitHubToken?
    private var loaded = false
    /// The in-flight refresh, shared by concurrent callers (single-flight).
    private var refreshTask: Task<GitHubToken, Error>?

    public init(
        flow: GitHubDeviceFlow,
        store: any TokenStore,
        clock: any Clock = SystemClock(),
        refreshBuffer: TimeInterval = 1800
    ) {
        self.flow = flow
        self.store = store
        self.clock = clock
        self.refreshBuffer = refreshBuffer
    }

    /// Read from the Keychain once, then serve the cached value.
    private func currentToken() throws -> GitHubToken? {
        if !loaded {
            cachedToken = try store.load()
            loaded = true
        }
        return cachedToken
    }

    /// Persist a token and update the in-memory cache together.
    private func persist(_ token: GitHubToken) throws {
        try store.save(token)
        cachedToken = token
        loaded = true
    }

    /// Whether a token is stored (i.e. the user has connected). Uses the cache.
    public func isConnected() -> Bool {
        ((try? currentToken()) ?? nil) != nil
    }

    /// A currently-valid access token, refreshing first if it's about to expire.
    /// Reads the Keychain only on the first call; refresh re-saves + re-caches.
    ///
    /// Refresh is **single-flight**: GitHub App refresh tokens are single-use, so
    /// two concurrent callers must not each fire a refresh (the second would
    /// reuse a spent token and can invalidate the whole grant). Concurrent
    /// callers await one shared refresh task instead.
    public func validAccessToken() async throws -> String {
        guard let token = try currentToken() else { throw GitHubAuthError.notConnected }

        guard token.isExpiring(within: refreshBuffer, now: clock.now()) else {
            return token.accessToken
        }
        guard token.refreshToken != nil else { throw GitHubAuthError.cannotRefresh }

        // Join an in-flight refresh if one exists…
        if let existing = refreshTask {
            return try await existing.value.accessToken
        }
        // …otherwise start it, and clear the slot when done so a later expiry
        // can refresh again.
        let newTask = Task { [self] in try await performRefresh() }
        refreshTask = newTask
        defer { refreshTask = nil }
        return try await newTask.value.accessToken
    }

    /// The actual refresh, run once by the single-flight task above.
    private func performRefresh() async throws -> GitHubToken {
        guard let current = try currentToken(), let refreshToken = current.refreshToken else {
            throw GitHubAuthError.cannotRefresh
        }
        let refreshed = try await flow.refresh(refreshToken: refreshToken, now: clock.now())
        try persist(refreshed)
        return refreshed
    }

    /// Start a device login. Present the returned `userCode` + `verificationUri`
    /// to the user, then call `awaitAuthorization`.
    public func beginDeviceLogin() async throws -> DeviceCodeResponse {
        try await flow.requestDeviceCode()
    }

    /// Poll until the user authorizes (or the code expires), saving the token on
    /// success. `sleep` is injectable so tests don't actually wait.
    public func awaitAuthorization(
        _ code: DeviceCodeResponse,
        sleep: @Sendable (TimeInterval) async -> Void = { seconds in
            _ = try? await Task.sleep(for: .seconds(seconds))
        }
    ) async throws {
        var interval = TimeInterval(max(code.interval, 1))
        let deadline = clock.now().addingTimeInterval(TimeInterval(code.expiresIn))

        while clock.now() < deadline {
            await sleep(interval)
            switch try await flow.poll(deviceCode: code.deviceCode, now: clock.now()) {
            case .authorized(let token):
                try persist(token)
                return
            case .pending:
                continue
            case .slowDown(let seconds):
                interval = TimeInterval(seconds)
            }
        }
        throw GitHubAuthError.deviceCodeExpired
    }

    /// Sign in with a Personal Access Token instead of the device flow. A PAT is
    /// a non-expiring token, so it slots into the same store and needs no
    /// refresh — and it can read every repo the user has access to (including
    /// private org repos the GitHub App isn't installed on).
    public func signIn(withPersonalAccessToken pat: String) throws {
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = GitHubToken(accessToken: trimmed, refreshToken: nil,
                                expiresAt: nil, refreshTokenExpiresAt: nil)
        try persist(token)
    }

    /// Forget the stored token, in the Keychain and in memory.
    public func signOut() throws {
        try store.clear()
        cachedToken = nil
        loaded = true
    }
}
