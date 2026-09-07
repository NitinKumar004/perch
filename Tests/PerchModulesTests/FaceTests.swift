import Testing
import Foundation
import PerchCore
import PerchModuleKit
@testable import PerchModules

// The face(_:) mappings are pure functions — the visible contract of each
// module — so they're worth pinning: a passing build must read green, a
// pegged CPU must read red, and a nonzero PR queue must read as attention.

private func series(_ v: Int) -> VitalSeries { VitalSeries(current: v, history: [v]) }

@Test func contextBoolAndIntHelpers() {
    #expect(ModuleContext(settings: [:]).bool("showChecks", fallback: true) == true)
    #expect(ModuleContext(settings: ["showChecks": "false"]).bool("showChecks", fallback: true) == false)
    #expect(ModuleContext(settings: ["limit": "5"]).int("limit", fallback: 8) == 5)
    #expect(ModuleContext(settings: ["limit": "999"]).int("limit", fallback: 8, maximum: 25) == 25) // clamped
    #expect(ModuleContext(settings: ["limit": "bad"]).int("limit", fallback: 8) == 8)
}

@Test func prDetailHonorsDisplayToggles() {
    let m = GitHubPRsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    let pr = PRSummary(number: 1, title: "t", repo: "o/r", url: "u",
                       reviewDecision: "APPROVED", mergeable: "MERGEABLE",
                       isDraft: false, checksState: "PENDING")
    // Both on → subtitle mentions CI and review.
    let both = m.detail(for: PRState(count: 1, items: [pr], showChecks: true, showReview: true))[0]
    #expect(both.subtitle?.contains("CI running") == true)
    #expect(both.subtitle?.contains("approved") == true)
    // CI off → no CI text.
    let noCI = m.detail(for: PRState(count: 1, items: [pr], showChecks: false, showReview: true))[0]
    #expect(noCI.subtitle?.contains("CI") == false)
}

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

@Test func prParseReposHandlesOneManyOrBlank() {
    #expect(GitHubPRsModule.parseRepos("") == [])                          // blank = all repos
    #expect(GitHubPRsModule.parseRepos("acme/api") == ["acme/api"])        // one
    #expect(GitHubPRsModule.parseRepos("acme/api, acme/web") == ["acme/api", "acme/web"])
    #expect(GitHubPRsModule.parseRepos("acme/api acme/web") == ["acme/api", "acme/web"]) // spaces
    #expect(GitHubPRsModule.parseRepos("garbage, acme/api") == ["acme/api"]) // needs a slash
}

@Test func prsFaceGoesQuietAtZero() {
    let m = GitHubPRsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    #expect(m.face(for: PRState(count: 0, items: []), in: .rightPill).tint == .neutral)
    #expect(m.face(for: PRState(count: 3, items: []), in: .rightPill).tint == .warning)
    #expect(m.face(for: PRState(count: 3, items: []), in: .rightPill).text == "3")
    // A no-access scoped repo must NOT look like a calm "0 PRs".
    let na = m.face(for: PRState(count: 0, items: [], repoScope: "acme/private", noAccess: true), in: .rightPill)
    #expect(na.text == "PR ?")
    #expect(na.tint == .warning)

    // Unresolved threads → the pill stays a calm count with an attention DOT
    // (no scary "6 · 54"); the exact number is only in the tooltip.
    func prItem(unresolved: Int) -> PRSummary {
        PRSummary(number: 1, title: "t", repo: "o/r", url: "u", unresolvedThreads: unresolved)
    }
    let owed = m.face(for: PRState(count: 6, items: [prItem(unresolved: 40), prItem(unresolved: 14)]), in: .rightPill)
    #expect(owed.text == "6")               // count only, not "6 · 54"
    #expect(owed.badge == .critical)        // the attention dot
    #expect(owed.tooltip?.contains("54 review threads to resolve") == true)  // exact count in tooltip
    // No unresolved threads → no badge.
    let clean = m.face(for: PRState(count: 6, items: [prItem(unresolved: 0)]), in: .rightPill)
    #expect(clean.badge == nil)
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
    func pr(_ review: String?, mergeable: String? = "MERGEABLE", draft: Bool = false,
            checks: String? = nil, unresolved: Int = 0) -> PRSummary {
        PRSummary(number: 1, title: "t", repo: "o/r", url: "u",
                  reviewDecision: review, mergeable: mergeable, isDraft: draft,
                  checksState: checks, unresolvedThreads: unresolved)
    }
    #expect(GitHubPRsModule.status(for: pr("APPROVED")).tint == .good)
    #expect(GitHubPRsModule.status(for: pr("REVIEW_REQUIRED")).tint == .warning)
    #expect(GitHubPRsModule.status(for: pr(nil, mergeable: "CONFLICTING")).label == "conflicts")
    #expect(GitHubPRsModule.status(for: pr("APPROVED", draft: true)).label == "draft")

    // "changes requested" is actionable: unresolved threads ⇒ your move; none ⇒
    // you've addressed them and it's waiting on the reviewer's re-review.
    let toResolve = GitHubPRsModule.status(for: pr("CHANGES_REQUESTED", unresolved: 3))
    #expect(toResolve.label == "3 to resolve")
    #expect(toResolve.tint == .critical)
    let awaiting = GitHubPRsModule.status(for: pr("CHANGES_REQUESTED", unresolved: 0))
    #expect(awaiting.label == "awaiting re-review")
    #expect(awaiting.tint == .warning)

    // Ready to merge: approved + CI green + no conflict + not draft.
    let ready = GitHubPRsModule.status(for: pr("APPROVED", checks: "SUCCESS"))
    #expect(ready.label == "ready to merge")
    #expect(ready.tint == .good)
    // Approved but CI still running → not ready yet.
    #expect(GitHubPRsModule.status(for: pr("APPROVED", checks: "PENDING")).label == "approved")
}

@Test func prReadyToMergeFlag() {
    func pr(review: String?, checks: String?, mergeable: String? = "MERGEABLE", draft: Bool = false) -> PRSummary {
        PRSummary(number: 1, title: "t", repo: "o/r", url: "u",
                  reviewDecision: review, mergeable: mergeable, isDraft: draft, checksState: checks)
    }
    #expect(pr(review: "APPROVED", checks: "SUCCESS").isReadyToMerge)
    #expect(!pr(review: "APPROVED", checks: "FAILURE").isReadyToMerge)
    #expect(!pr(review: "CHANGES_REQUESTED", checks: "SUCCESS").isReadyToMerge)
    #expect(!pr(review: "APPROVED", checks: "SUCCESS", mergeable: "CONFLICTING").isReadyToMerge)
    #expect(!pr(review: "APPROVED", checks: "SUCCESS", draft: true).isReadyToMerge)
    // Mergeability still being computed (UNKNOWN) or absent must NOT read as
    // ready — that's a false green that flips to CONFLICTING moments later.
    #expect(!pr(review: "APPROVED", checks: "SUCCESS", mergeable: "UNKNOWN").isReadyToMerge)
    #expect(!pr(review: "APPROVED", checks: "SUCCESS", mergeable: nil).isReadyToMerge)
}

@Test func prCIStatusMapping() {
    #expect(GitHubPRsModule.ciStatus("SUCCESS")?.label == "CI passing")
    #expect(GitHubPRsModule.ciStatus("SUCCESS")?.tint == .good)
    #expect(GitHubPRsModule.ciStatus("FAILURE")?.tint == .critical)
    #expect(GitHubPRsModule.ciStatus("ERROR")?.tint == .critical)
    #expect(GitHubPRsModule.ciStatus("PENDING")?.label == "CI running")
    #expect(GitHubPRsModule.ciStatus(nil) == nil)          // no checks → no clutter
    #expect(GitHubPRsModule.ciStatus("EXPECTED") == nil)
}

@Test func prCIProgressReadsAsFraction() {
    // A running pipeline with known counts reads "CI 5/10" and drives a bar.
    let running = GitHubPRsModule.ciStatus("PENDING", done: 5, total: 10)
    #expect(running?.label == "CI 5/10")
    #expect(running?.tint == .info)
    #expect(running?.progress == 0.5)
    // Passing never shows a bar (nothing left to complete).
    #expect(GitHubPRsModule.ciStatus("SUCCESS", done: 10, total: 10)?.progress == nil)
    // A failing run still shows how far it got.
    #expect(GitHubPRsModule.ciStatus("FAILURE", done: 3, total: 4)?.progress == 0.75)
    // No counts → plain "CI running", no bar.
    #expect(GitHubPRsModule.ciStatus("PENDING")?.label == "CI running")
    #expect(GitHubPRsModule.ciStatus("PENDING")?.progress == nil)
}

@Test func clockRendersChosenFormat() {
    var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 6
    comps.hour = 14; comps.minute = 30; comps.second = 7
    let date = Calendar.current.date(from: comps)!
    #expect(ClockModule.render(date, twelveHour: false, showSeconds: false).text == "14:30")
    #expect(ClockModule.render(date, twelveHour: false, showSeconds: true).text == "14:30:07")
    #expect(ClockModule.render(date, twelveHour: true, showSeconds: false).text == "2:30 PM")
    var midnight = comps; midnight.hour = 0; midnight.minute = 5
    let mid = Calendar.current.date(from: midnight)!
    #expect(ClockModule.render(mid, twelveHour: true, showSeconds: false).text == "12:05 AM")
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

// MARK: - GitHub Notifications

@Test func notificationsFaceReflectsUnreadCount() {
    let m = GitHubNotificationsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    let zero = m.face(for: .empty, in: .rightPill)
    #expect(zero.text == "0")
    #expect(zero.tint == .neutral)
    #expect(zero.symbolName == "bell")
    func n(_ id: String, _ reason: String = "mention") -> NotificationThread {
        NotificationThread(id: id, reason: reason, title: "t", repo: "o/r",
                           subjectType: "Issue", apiURL: nil, updatedAt: Date())
    }
    let some = m.face(for: NotificationState(items: [n("1"), n("2"), n("3")]), in: .rightPill)
    #expect(some.text == "3")
    #expect(some.tint == .warning)
    #expect(some.symbolName == "bell.badge")
    // >50 unread (truncated) reads as "N+", never a silently-capped exact count.
    let many = m.face(for: NotificationState(items: [n("1")], truncated: true), in: .rightPill)
    #expect(many.text == "1+")
    #expect(many.tooltip?.contains("1+ unread") == true)
}

@Test func notificationsReasonMapping() {
    #expect(GitHubNotificationsModule.friendlyReason("review_requested") == "review requested")
    #expect(GitHubNotificationsModule.friendlyReason("ci_activity") == "CI activity")
    #expect(GitHubNotificationsModule.friendlyReason("team_mention") == "mentioned you")
    #expect(GitHubNotificationsModule.friendlyReason("weird_reason") == "weird reason")  // underscores humanised
    #expect(GitHubNotificationsModule.tint(for: "security_alert") == .critical)
    #expect(GitHubNotificationsModule.tint(for: "review_requested") == .warning)
    #expect(GitHubNotificationsModule.tint(for: "ci_activity") == .info)
    #expect(GitHubNotificationsModule.symbol(for: "mention") == "at")
}

@Test func notificationsAlertOnlyOnNewThread() {
    let m = GitHubNotificationsModule(client: .init(auth: .init(
        flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    func n(_ id: String) -> NotificationThread {
        NotificationThread(id: id, reason: "mention", title: "hi", repo: "o/r",
                           subjectType: "Issue", apiURL: nil, updatedAt: Date())
    }
    let prev = NotificationState(items: [n("1")])   // a real prior fetch
    // A brand-new thread id → alert; no new id → no alert; no prior → no alert.
    // (The cold-start "don't alert for pre-existing unread on launch" baseline is
    // enforced universally by AnyNotchModule — see AnyNotchModuleTests.)
    #expect(m.notification(for: NotificationState(items: [n("2"), n("1")]), previous: prev) != nil)
    #expect(m.notification(for: NotificationState(items: [n("1")]), previous: prev) == nil)
    #expect(m.notification(for: NotificationState(items: [n("1")]), previous: nil) == nil)
}

// MARK: - Data-accuracy fixes (network scope, battery state)

@Test func networkCountsOnlyPhysicalInterfaces() {
    #expect(NetworkReader.countsTowardThroughput("en0"))        // Wi-Fi/Ethernet
    #expect(NetworkReader.countsTowardThroughput("pdp_ip0"))    // cellular
    // Virtual/link-local must NOT count (they double-count or add chatter).
    #expect(!NetworkReader.countsTowardThroughput("lo0"))       // loopback
    #expect(!NetworkReader.countsTowardThroughput("utun3"))     // VPN tunnel
    #expect(!NetworkReader.countsTowardThroughput("awdl0"))     // AirDrop
    #expect(!NetworkReader.countsTowardThroughput("llw0"))      // Handoff
    #expect(!NetworkReader.countsTowardThroughput("bridge0"))   // sharing/Docker
    #expect(!NetworkReader.countsTowardThroughput("ap1"))       // hotspot
}

@Test func batteryFaceDistinguishesChargingVsPluggedVsBattery() {
    let m = BatteryModule()
    // Actually charging → bolt.
    let charging = m.face(for: BatterySample(percent: 60, isCharging: true, isPluggedIn: true, hasBattery: true), in: .rightPill)
    #expect(charging.symbolName == "battery.100.bolt")
    #expect(charging.tooltip?.contains("Charging") == true)
    // On AC but NOT charging (full / held at 80%) → plug, honest tooltip (was wrongly "Charging").
    let plugged = m.face(for: BatterySample(percent: 100, isCharging: false, isPluggedIn: true, hasBattery: true), in: .rightPill)
    #expect(plugged.symbolName == "powerplug")
    #expect(plugged.tooltip?.contains("not charging") == true)
    // On battery → battery glyph.
    let onBattery = m.face(for: BatterySample(percent: 55, isCharging: false, isPluggedIn: false, hasBattery: true), in: .rightPill)
    #expect(onBattery.tooltip?.contains("On battery") == true)
}
