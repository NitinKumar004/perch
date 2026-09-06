import Testing
import PerchCore
import PerchModuleKit
@testable import PerchModules

// The face(_:) mappings are pure functions — the visible contract of each
// module — so they're worth pinning: a passing build must read green, a
// pegged CPU must read red, and a nonzero PR queue must read as attention.

private func series(_ v: Int) -> VitalSeries { VitalSeries(current: v, history: [v]) }

@Test func refreshSecondsHelperParsesAndClamps() {
    #expect(ModuleContext(settings: [:]).refreshSeconds(fallback: 60) == 60)      // unset → fallback
    #expect(ModuleContext(settings: ["refreshSeconds": "30"]).refreshSeconds(fallback: 60) == 30)
    #expect(ModuleContext(settings: ["refreshSeconds": "1"]).refreshSeconds(fallback: 60, minimum: 15) == 15) // clamped
    #expect(ModuleContext(settings: ["refreshSeconds": "junk"]).refreshSeconds(fallback: 60) == 60) // bad → fallback
}

@Test func vitalsTintCrossesThresholds() {
    let m = VitalsModule()
    #expect(m.face(for: series(10), in: .rightPill).tint == .good)
    #expect(m.face(for: series(75), in: .rightPill).tint == .warning)
    #expect(m.face(for: series(95), in: .rightPill).tint == .critical)
    // Labeled so it's never confused with another vitals pill.
    #expect(m.face(for: series(27), in: .rightPill).text == "CPU 27%")
}

@Test func memoryFaceIsLabelledAndDistinct() {
    let m = MemoryModule()
    #expect(m.face(for: series(61), in: .rightPill).text == "RAM 61%")
    #expect(m.face(for: series(61), in: .rightPill).symbolName == "memorychip")
    #expect(m.face(for: series(40), in: .rightPill).tint == .good)
    #expect(m.face(for: series(80), in: .rightPill).tint == .warning)
    #expect(m.face(for: series(95), in: .rightPill).tint == .critical)
}

@Test func vitalsDetailHasSparkline() {
    let m = VitalsModule()
    let rows = m.detail(for: VitalSeries(current: 30, history: [10, 20, 30]))
    #expect(rows.count == 1)
    #expect(rows[0].sparkline == [10, 20, 30])
    #expect(rows[0].subtitle == "30%")
}

@Test func buildNotifiesOnTurningRed() {
    let m = FakeBuildModule()  // uses BuildState; exercises default nil notification
    #expect(m.notification(for: .failing, previous: .passing) == nil)  // FakeBuild has no override
}

@Test func prsFaceGoesQuietAtZero() {
    let m = GitHubPRsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    #expect(m.face(for: PRState(count: 0, items: []), in: .rightPill).tint == .neutral)
    #expect(m.face(for: PRState(count: 3, items: []), in: .rightPill).tint == .warning)
    #expect(m.face(for: PRState(count: 3, items: []), in: .rightPill).text == "3")
}

@Test func prsDetailListsPRsWithLinks() {
    let m = GitHubPRsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    let state = PRState(count: 2, items: [
        PRSummary(number: 2533, title: "ClickHouse billing", repo: "zopdev/zopnight", url: "https://github.com/zopdev/zopnight/pull/2533"),
        PRSummary(number: 2716, title: "dep align", repo: "zopdev/zopnight", url: "https://github.com/zopdev/zopnight/pull/2716"),
    ])
    let rows = m.detail(for: state)
    #expect(rows.count == 2)
    #expect(rows[0].title == "#2533 ClickHouse billing")
    #expect(rows[0].url == "https://github.com/zopdev/zopnight/pull/2533")
    #expect(rows[0].subtitle?.hasPrefix("zopdev/zopnight") == true)
}

@Test func prStatusBadgeMapping() {
    func pr(_ review: String?, mergeable: String? = nil, draft: Bool = false) -> PRSummary {
        PRSummary(number: 1, title: "t", repo: "o/r", url: "u",
                  reviewDecision: review, mergeable: mergeable, isDraft: draft)
    }
    #expect(GitHubPRsModule.status(for: pr("APPROVED")).tint == .good)
    #expect(GitHubPRsModule.status(for: pr("CHANGES_REQUESTED")).tint == .critical)
    #expect(GitHubPRsModule.status(for: pr("REVIEW_REQUIRED")).tint == .warning)
    #expect(GitHubPRsModule.status(for: pr(nil, mergeable: "CONFLICTING")).label == "conflicts")
    #expect(GitHubPRsModule.status(for: pr("APPROVED", draft: true)).label == "draft")
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
