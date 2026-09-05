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

    /// Whether a token is stored (i.e. the user has connected).
    public func isConnected() -> Bool {
        ((try? store.load()) ?? nil) != nil
    }

    /// A currently-valid access token, refreshing first if it's about to expire.
    public func validAccessToken() async throws -> String {
        guard let token = try store.load() else { throw GitHubAuthError.notConnected }

        if token.isExpiring(within: refreshBuffer, now: clock.now()) {
            guard let refreshToken = token.refreshToken else { throw GitHubAuthError.cannotRefresh }
            let refreshed = try await flow.refresh(refreshToken: refreshToken, now: clock.now())
            try store.save(refreshed)
            return refreshed.accessToken
        }
        return token.accessToken
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
                try store.save(token)
                return
            case .pending:
                continue
            case .slowDown(let seconds):
                interval = TimeInterval(seconds)
            }
        }
        throw GitHubAuthError.deviceCodeExpired
    }

    /// Forget the stored token.
    public func signOut() throws {
        try store.clear()
    }
}
