import Testing
import PerchCore
import PerchModuleKit
@testable import PerchModules

// The face(_:) mappings are pure functions — the visible contract of each
// module — so they're worth pinning: a passing build must read green, a
// pegged CPU must read red, and a nonzero PR queue must read as attention.

@Test func vitalsTintCrossesThresholds() {
    let m = VitalsModule()
    #expect(m.face(for: 10, in: .rightPill).tint == .good)
    #expect(m.face(for: 75, in: .rightPill).tint == .warning)
    #expect(m.face(for: 95, in: .rightPill).tint == .critical)
}

@Test func prsFaceGoesQuietAtZero() {
    let m = GitHubPRsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    #expect(m.face(for: 0, in: .rightPill).tint == .neutral)
    #expect(m.face(for: 3, in: .rightPill).tint == .warning)
    #expect(m.face(for: 3, in: .rightPill).text == "3")
}

@Test func buildFaceColors() {
    let m = FakeBuildModule()
    #expect(m.face(for: .passing, in: .leftPill).tint == .good)
    #expect(m.face(for: .failing, in: .leftPill).tint == .critical)
    #expect(m.face(for: .running, in: .leftPill).tint == .info)
}

// Minimal doubles so the PR module can be constructed without a network.
import PerchGitHub
private struct NoopHTTP: HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { HTTPResponse(status: 0, body: .init()) }
}
private struct NoopStore: TokenStore {
    func load() throws -> GitHubToken? { nil }
    func save(_ token: GitHubToken) throws {}
    func clear() throws {}
}
