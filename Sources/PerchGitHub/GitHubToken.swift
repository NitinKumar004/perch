import Foundation

/// A stored GitHub user-to-server token. GitHub App tokens expire (≈8h) and
/// come with a refresh token (≈6mo), so we keep both plus their expiry so the
/// auth layer can refresh silently before a call fails.
public struct GitHubToken: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    /// When the access token stops working. `nil` means a non-expiring token.
    public let expiresAt: Date?
    public let refreshTokenExpiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        refreshTokenExpiresAt: Date?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    /// True if the access token will expire within `buffer` seconds of `now`.
    /// A non-expiring token is never "expiring".
    public func isExpiring(within buffer: TimeInterval, now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= buffer
    }
}
