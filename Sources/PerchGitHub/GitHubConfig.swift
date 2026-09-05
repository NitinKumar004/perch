import Foundation

/// Static configuration for the GitHub integration.
///
/// The client id is the **public** identifier of the Perch GitHub App. It is
/// safe to ship in the binary and commit to source — device flow is a "public
/// client" grant that never uses a client secret, which is exactly why it fits
/// an unsigned, freely-distributed desktop app.
public enum GitHubConfig {
    /// Perch GitHub App — public client id (device flow, no secret).
    public static let clientID = "Iv23li0zP14V8DTpSPPk"

    public static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    public static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    public static let apiBaseURL = URL(string: "https://api.github.com")!
}
