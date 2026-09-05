import Foundation

/// What GitHub hands back when you request a device code: the code the user
/// types, where to type it, and how long/often to poll.
public struct DeviceCodeResponse: Decodable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int
}

/// The outcome of a single poll while waiting for the user to authorize.
public enum DevicePollResult: Sendable, Equatable {
    case pending
    case slowDown(Int)
    case authorized(GitHubToken)
}

/// Implements GitHub's OAuth **device flow** for a GitHub App — the "type this
/// code at github.com" login that needs no client secret and no callback
/// server, which is what makes it a clean fit for a desktop app.
public struct GitHubDeviceFlow: Sendable {
    private let http: any HTTPClient
    private let clientID: String

    public init(http: any HTTPClient, clientID: String = GitHubConfig.clientID) {
        self.http = http
        self.clientID = clientID
    }

    /// Step 1: ask GitHub for a device + user code.
    public func requestDeviceCode() async throws -> DeviceCodeResponse {
        let response = try await post(
            GitHubConfig.deviceCodeURL,
            form: ["client_id": clientID]
        )
        try Self.ensureOK(response)
        guard let value = try? Self.decoder.decode(DeviceCodeResponse.self, from: response.body) else {
            throw GitHubAuthError.decoding
        }
        return value
    }

    /// Step 2: poll once for the access token. Returns `.pending`/`.slowDown`
    /// while the user hasn't finished, `.authorized` once they have.
    public func poll(deviceCode: String, now: Date) async throws -> DevicePollResult {
        let response = try await post(
            GitHubConfig.accessTokenURL,
            form: [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ]
        )
        try Self.ensureOK(response)
        let raw = try Self.decodeToken(response.body)

        if let token = raw.token(now: now) {
            return .authorized(token)
        }
        switch raw.error {
        case "authorization_pending": return .pending
        case "slow_down":             return .slowDown(raw.interval ?? 5)
        case "expired_token":         throw GitHubAuthError.deviceCodeExpired
        case "access_denied":         throw GitHubAuthError.accessDenied
        case let other?:              throw GitHubAuthError.oauth(code: other, description: raw.errorDescription)
        case nil:                     throw GitHubAuthError.decoding
        }
    }

    /// Exchange a refresh token for a fresh access token.
    public func refresh(refreshToken: String, now: Date) async throws -> GitHubToken {
        let response = try await post(
            GitHubConfig.accessTokenURL,
            form: [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ]
        )
        try Self.ensureOK(response)
        let raw = try Self.decodeToken(response.body)
        guard let token = raw.token(now: now) else {
            throw GitHubAuthError.oauth(code: raw.error ?? "unknown", description: raw.errorDescription)
        }
        return token
    }

    // MARK: - Internals

    private func post(_ url: URL, form: [String: String]) async throws -> HTTPResponse {
        let request = HTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded",
            ],
            body: Data(Self.encodeForm(form).utf8)
        )
        return try await http.send(request)
    }

    private static func ensureOK(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.status) else {
            throw GitHubAuthError.http(status: response.status)
        }
    }

    private static func encodeForm(_ form: [String: String]) -> String {
        form.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func decodeToken(_ data: Data) throws -> RawTokenResponse {
        guard let raw = try? decoder.decode(RawTokenResponse.self, from: data) else {
            throw GitHubAuthError.decoding
        }
        return raw
    }
}

/// The union of GitHub's success and error token responses, decoded leniently
/// (every field optional) so one type covers both shapes.
private struct RawTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let error: String?
    let errorDescription: String?
    let interval: Int?

    /// Build a `GitHubToken` if this response actually carried an access token.
    func token(now: Date) -> GitHubToken? {
        guard let accessToken else { return nil }
        return GitHubToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { now.addingTimeInterval(TimeInterval($0)) },
            refreshTokenExpiresAt: refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        )
    }
}
