import Foundation

/// Everything that can go wrong while authenticating with GitHub, as a typed,
/// matchable error so callers can react precisely (e.g. show "denied" vs "retry").
public enum GitHubAuthError: Error, Equatable, Sendable {
    /// No token has been stored yet — the user hasn't connected.
    case notConnected
    /// A non-2xx HTTP response, with the status code.
    case http(status: Int)
    /// The response body could not be decoded as expected.
    case decoding
    /// GitHub returned an OAuth error (`error` + optional description).
    case oauth(code: String, description: String?)
    /// The device code expired before the user finished authorizing.
    case deviceCodeExpired
    /// The user explicitly denied the authorization.
    case accessDenied
    /// The token is expired and cannot be refreshed (no refresh token).
    case cannotRefresh
    /// A Keychain read/write failed, with the OSStatus.
    case keychain(status: Int32)
}
