import Testing
import Foundation
import PerchCore
@testable import PerchGitHub

// MARK: - Test doubles

/// Returns canned responses in order, and records what was sent.
actor FakeHTTPClient: HTTPClient {
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(_ responses: [HTTPResponse]) { self.responses = responses }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { return HTTPResponse(status: 500, body: Data()) }
        return responses.removeFirst()
    }

    var requestCount: Int { requests.count }
}

final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
}

private func json(_ string: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, body: Data(string.utf8))
}

private let epoch = Date(timeIntervalSince1970: 1_000_000)

// MARK: - Device flow

@Test func requestDeviceCodeDecodes() async throws {
    let http = FakeHTTPClient([json(#"""
    {"device_code":"DC123","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
    """#)])
    let flow = GitHubDeviceFlow(http: http, clientID: "cid")

    let code = try await flow.requestDeviceCode()

    #expect(code.deviceCode == "DC123")
    #expect(code.userCode == "WDJB-MJHT")
    #expect(code.verificationUri == "https://github.com/login/device")
    #expect(code.interval == 5)
}

@Test func pollReturnsPendingThenAuthorized() async throws {
    let http = FakeHTTPClient([
        json(#"{"error":"authorization_pending"}"#),
        json(#"""
        {"access_token":"gho_x","token_type":"bearer","expires_in":28800,"refresh_token":"ghr_y","refresh_token_expires_in":15897600}
        """#),
    ])
    let flow = GitHubDeviceFlow(http: http, clientID: "cid")

    let pending = try await flow.poll(deviceCode: "DC", now: epoch)
    #expect(pending == .pending)

    let result = try await flow.poll(deviceCode: "DC", now: epoch)
    guard case .authorized(let token) = result else {
        Issue.record("expected authorized"); return
    }
    #expect(token.accessToken == "gho_x")
    #expect(token.refreshToken == "ghr_y")
    #expect(token.expiresAt == epoch.addingTimeInterval(28800))
}

@Test func pollSurfacesAccessDenied() async throws {
    let http = FakeHTTPClient([json(#"{"error":"access_denied"}"#)])
    let flow = GitHubDeviceFlow(http: http, clientID: "cid")
    await #expect(throws: GitHubAuthError.accessDenied) {
        _ = try await flow.poll(deviceCode: "DC", now: epoch)
    }
}

// MARK: - Auth orchestration

@Test func validAccessTokenRefreshesWhenExpiring() async throws {
    let clock = TestClock(epoch)
    let expiring = GitHubToken(
        accessToken: "old",
        refreshToken: "ghr",
        expiresAt: epoch.addingTimeInterval(60),          // within the 1800s buffer
        refreshTokenExpiresAt: epoch.addingTimeInterval(999_999)
    )
    let store = InMemoryTokenStore(expiring)
    let http = FakeHTTPClient([json(#"""
    {"access_token":"new","token_type":"bearer","expires_in":28800,"refresh_token":"ghr2","refresh_token_expires_in":15897600}
    """#)])
    let auth = GitHubAuth(flow: GitHubDeviceFlow(http: http, clientID: "cid"),
                          store: store, clock: clock, refreshBuffer: 1800)

    let token = try await auth.validAccessToken()

    #expect(token == "new")
    #expect((try store.load())?.accessToken == "new")
    #expect(await http.requestCount == 1) // it actually refreshed
}

@Test func concurrentCallersRefreshOnlyOnce() async throws {
    // Single-flight: many callers hitting an expiring token must trigger just
    // one refresh, not one per caller (refresh tokens are single-use).
    let clock = TestClock(epoch)
    let expiring = GitHubToken(accessToken: "old", refreshToken: "ghr",
                               expiresAt: epoch.addingTimeInterval(60),
                               refreshTokenExpiresAt: epoch.addingTimeInterval(999_999))
    let http = FakeHTTPClient([json(#"""
    {"access_token":"new","token_type":"bearer","expires_in":28800,"refresh_token":"ghr2","refresh_token_expires_in":15897600}
    """#)])
    let auth = GitHubAuth(flow: GitHubDeviceFlow(http: http, clientID: "cid"),
                          store: InMemoryTokenStore(expiring), clock: clock, refreshBuffer: 1800)

    // Fire 10 concurrent token requests.
    let tokens = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<10 { group.addTask { try await auth.validAccessToken() } }
        var all: [String] = []
        for try await t in group { all.append(t) }
        return all
    }

    #expect(tokens.allSatisfy { $0 == "new" })
    #expect(await http.requestCount == 1)  // exactly one refresh, not ten
}

@Test func validAccessTokenReturnsExistingWhenFresh() async throws {
    let clock = TestClock(epoch)
    let fresh = GitHubToken(accessToken: "keep", refreshToken: "r",
                            expiresAt: epoch.addingTimeInterval(100_000), refreshTokenExpiresAt: nil)
    let http = FakeHTTPClient([])
    let auth = GitHubAuth(flow: GitHubDeviceFlow(http: http, clientID: "cid"),
                          store: InMemoryTokenStore(fresh), clock: clock)

    let token = try await auth.validAccessToken()

    #expect(token == "keep")
    #expect(await http.requestCount == 0) // no network needed
}

@Test func validAccessTokenThrowsWhenNotConnected() async throws {
    let auth = GitHubAuth(flow: GitHubDeviceFlow(http: FakeHTTPClient([]), clientID: "cid"),
                          store: InMemoryTokenStore(nil), clock: TestClock(epoch))
    await #expect(throws: GitHubAuthError.notConnected) {
        _ = try await auth.validAccessToken()
    }
}

// MARK: - API client classification

private func connectedAuth() -> GitHubAuth {
    let fresh = GitHubToken(accessToken: "t", refreshToken: nil,
                            expiresAt: epoch.addingTimeInterval(999_999), refreshTokenExpiresAt: nil)
    return GitHubAuth(flow: GitHubDeviceFlow(http: FakeHTTPClient([]), clientID: "cid"),
                      store: InMemoryTokenStore(fresh), clock: TestClock(epoch))
}

private func runsJSON(status: String, conclusion: String?) -> String {
    let concl = conclusion.map { "\"\($0)\"" } ?? "null"
    return """
    {"total_count":1,"workflow_runs":[{"id":1,"status":"\(status)","conclusion":\(concl),"updated_at":"2026-09-05T09:00:00Z","html_url":"https://github.com/o/r/actions/runs/1","run_number":1}]}
    """
}

/// Unwrap the observation from a BuildFetch (nil for notModified/no-runs).
private func observation(_ fetch: GitHubAPIClient.BuildFetch) -> BuildObservation? {
    if case .ok(let obs, _) = fetch { return obs }
    return nil
}

@Test func latestBuildClassifiesSuccessAsPassing() async throws {
    let http = FakeHTTPClient([json(runsJSON(status: "completed", conclusion: "success"))])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    let obs = observation(try await client.latestBuild(owner: "o", repo: "r", branch: "main", etag: nil))
    #expect(obs?.state == .passing)
    #expect(obs?.url == "https://github.com/o/r/actions/runs/1")
}

@Test func latestBuildClassifiesInProgressAsRunning() async throws {
    let http = FakeHTTPClient([json(runsJSON(status: "in_progress", conclusion: nil))])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    let obs = observation(try await client.latestBuild(owner: "o", repo: "r", branch: "main", etag: nil))
    #expect(obs?.state == .running)
}

@Test func latestBuildClassifiesFailureAsFailing() async throws {
    let http = FakeHTTPClient([json(runsJSON(status: "completed", conclusion: "failure"))])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    let obs = observation(try await client.latestBuild(owner: "o", repo: "r", branch: "main", etag: nil))
    #expect(obs?.state == .failing)
}

@Test func latestBuildReturnsNilWhenNoRuns() async throws {
    let http = FakeHTTPClient([json(#"{"total_count":0,"workflow_runs":[]}"#)])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    let obs = observation(try await client.latestBuild(owner: "o", repo: "r", branch: "main", etag: nil))
    #expect(obs == nil)
}

@Test func latestBuild304ReturnsNotModified() async throws {
    let http = FakeHTTPClient([HTTPResponse(status: 304, body: Data())])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    let fetch = try await client.latestBuild(owner: "o", repo: "r", branch: "main", etag: "\"abc\"")
    guard case .notModified = fetch else { Issue.record("expected notModified"); return }
}

@Test func pullRequestCountReadsTotalCount() async throws {
    let http = FakeHTTPClient([json(#"{"total_count":2,"incomplete_results":false,"items":[]}"#)])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    let obs = try await client.pullRequestCount(queue: .reviewRequested, repo: nil, now: epoch)
    #expect(obs.count == 2)
    #expect(obs.observedAt == epoch)
}

@Test func pullRequestCountScopesToRepoInQuery() async throws {
    let http = FakeHTTPClient([json(#"{"total_count":0,"items":[]}"#)])
    let client = GitHubAPIClient(http: http, auth: connectedAuth())
    _ = try await client.pullRequestCount(queue: .authored, repo: "acme/api", now: epoch)

    let sent = await http.requests.first
    let url = sent?.url.absoluteString ?? ""
    #expect(url.contains("search/issues"))
    #expect(url.contains("author:@me") || url.contains("author%3A@me") || url.contains("author"))
    #expect(url.contains("acme/api") || url.contains("acme%2Fapi"))
}
