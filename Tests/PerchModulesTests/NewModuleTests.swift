import Testing
import Foundation
import PerchCore
import PerchModuleKit
@testable import PerchModules

// MARK: - Timer

@Test func timerFormatsRemaining() {
    #expect(TimerModule.format(1500) == "25:00")
    #expect(TimerModule.format(65) == "1:05")
    #expect(TimerModule.format(9) == "0:09")
}

@Test func timerFaceDoneAtZero() {
    let m = TimerModule(controller: TimerController())
    func s(_ r: Int, paused: Bool = false) -> TimerState { TimerState(remaining: r, isPaused: paused, id: "25") }
    #expect(m.face(for: s(0), in: .rightPill).tint == .good)
    #expect(m.face(for: s(300), in: .rightPill).tint == .accent)
    #expect(m.face(for: s(300), in: .rightPill).text == "5:00")
    // Detail rows expose pause + reset controls.
    let rows = m.detail(for: s(300))
    #expect(rows.contains { $0.action == "timer.toggle:25" })
    #expect(rows.contains { $0.action == "timer.reset:25" })
    #expect(m.face(for: s(300, paused: true), in: .rightPill).symbolName == "pause.circle")
}

@Test func timerControllerPausesAndResets() async {
    let c = TimerController()
    let t0 = Date(timeIntervalSince1970: 1000)
    // 10s elapse while running.
    _ = await c.elapsed(id: "x", now: t0)
    let e1 = await c.elapsed(id: "x", now: t0.addingTimeInterval(10))
    #expect(Int(e1.elapsed) == 10)
    // Pause at t0+10, then 100s of wall time pass — elapsed stays ~10.
    await c.togglePause(id: "x", now: t0.addingTimeInterval(10))
    let paused = await c.elapsed(id: "x", now: t0.addingTimeInterval(110))
    #expect(paused.isPaused)
    #expect(Int(paused.elapsed) == 10)
    // Reset → back to zero, running.
    await c.reset(id: "x", now: t0.addingTimeInterval(110))
    let afterReset = await c.elapsed(id: "x", now: t0.addingTimeInterval(115))
    #expect(!afterReset.isPaused)
    #expect(Int(afterReset.elapsed) == 5)
}

// MARK: - Deploy / health probe

@Test func healthProbeClassifiesStatus() async {
    let ok = HealthProbe { _ in 200 }
    let bad = HealthProbe { _ in 503 }
    let dead = HealthProbe { _ in nil }
    let url = URL(string: "https://example.com/health")!

    #expect(await ok.check(url) == .healthy)
    #expect(await bad.check(url) == .degraded)
    #expect(await dead.check(url) == .down)
}

@Test func deployFaceColors() {
    let m = DeployModule()
    #expect(m.face(for: .healthy, in: .leftPill).tint == .good)
    #expect(m.face(for: .degraded, in: .leftPill).tint == .warning)
    #expect(m.face(for: .down, in: .leftPill).tint == .critical)
}

// MARK: - Network

@Test func networkRateIsHumanReadable() {
    #expect(NetworkReader.humanRate(0) == "0 B/s")
    #expect(NetworkReader.humanRate(512) == "512 B/s")
    #expect(NetworkReader.humanRate(1536) == "1.5 KB/s")
    #expect(NetworkReader.humanRate(5 * 1024 * 1024) == "5.0 MB/s")
    #expect(NetworkReader.humanRate(-10) == "0 B/s")   // never negative
}

@Test func networkFaceShowsDownload() {
    let m = NetworkModule()
    let face = m.face(for: NetThroughput(downBytesPerSec: 2048, upBytesPerSec: 1024), in: .rightPill)
    #expect(face.text == "↓ 2.0 KB/s")
    let rows = m.detail(for: NetThroughput(downBytesPerSec: 2048, upBytesPerSec: 1024))
    #expect(rows.count == 2)
    #expect(rows[0].subtitle == "2.0 KB/s")
}

// MARK: - Multi-repo builds

@Test func multiBuildWorstAndCount() {
    func rb(_ repo: String, _ s: BuildState) -> RepoBuild { RepoBuild(repo: repo, state: s, url: "u") }
    let mixed = MultiBuildState(repos: [rb("a", .passing), rb("b", .failing), rb("c", .running)])
    #expect(mixed.worst == .failing)
    #expect(mixed.failingCount == 1)
    let running = MultiBuildState(repos: [rb("a", .passing), rb("b", .running)])
    #expect(running.worst == .running)
    #expect(MultiBuildState.empty.worst == .unknown)
}

@Test func multiBuildParsesReposAndFace() {
    #expect(MultiBuildsModule.parseRepos("owner/a, owner/b ,owner/c") == ["owner/a", "owner/b", "owner/c"])
    #expect(MultiBuildsModule.parseRepos("garbage, also-bad").isEmpty)   // need a slash
    let m = MultiBuildsModule(client: .init(auth: .init(flow: .init(http: NoopHTTP(), clientID: "x"), store: NoopStore())))
    let state = MultiBuildState(repos: [RepoBuild(repo: "o/a", state: .failing, url: "u")])
    #expect(m.face(for: state, in: .rightPill).text == "1✗")
    #expect(m.face(for: state, in: .rightPill).tint == .critical)
    #expect(m.detail(for: state)[0].url == "u")
}

// MARK: - Clipboard

@Test func clipboardControllerDedupesAndCaps() async {
    let c = ClipboardController(cap: 3)
    await c.record("one")
    await c.record("one")             // duplicate top → ignored
    await c.record("  ")              // blank → ignored
    await c.record("two")
    await c.record("three")
    await c.record("four")            // evicts "one"
    let snap = await c.snapshot()
    #expect(snap == ["four", "three", "two"])
    // Re-copying an older entry moves it to the top.
    await c.record("two")
    #expect(await c.snapshot() == ["two", "four", "three"])
    #expect(await c.entry(at: 0) == "two")
    #expect(await c.entry(at: 9) == nil)
    await c.clear()
    #expect(await c.snapshot().isEmpty)   // "Clear history" wipes it
}

@Test func clipboardPreviewAndRows() {
    #expect(ClipboardModule.preview("hello\nworld") == "hello world")
    #expect(ClipboardModule.preview(String(repeating: "x", count: 80)).hasSuffix("…"))
    let m = ClipboardModule(controller: ClipboardController())
    let rows = m.detail(for: ClipboardHistory(entries: ["first", "second"]))
    #expect(rows[0].action == "clip.copy:0")
    #expect(rows[0].subtitle == "on the clipboard now")
    #expect(rows[1].action == "clip.copy:1")
    // A trailing "Clear history" row wipes everything.
    #expect(rows.last?.action == "clip.clear:all")
    // Empty history shows a friendly placeholder, no actions.
    #expect(m.detail(for: .empty)[0].action == nil)
}

// MARK: - Port monitor

@Test func portFaceReflectsUpDown() {
    let m = PortMonitorModule()
    let up = m.face(for: PortStatus(port: 3000, isUp: true, label: ":3000"), in: .rightPill)
    #expect(up.tint == .good)
    let down = m.face(for: PortStatus(port: 3000, isUp: false, label: ":3000"), in: .rightPill)
    #expect(down.tint == .neutral)   // down is not an error → never red
    #expect(m.detail(for: PortStatus(port: 3000, isUp: true, label: ":3000"))[0].subtitle == "listening on 127.0.0.1:3000")
}

// MARK: - File shelf

@Test func fileShelfDedupesCapsAndShortens() async {
    let c = FileShelfController(cap: 2)
    await c.add(path: "/Users/me/a.txt")
    await c.add(path: "/Users/me/a.txt")     // dup → still one
    await c.add(path: "/Users/me/b.txt")
    await c.add(path: "/Users/me/c.txt")     // evicts a.txt
    let snap = await c.snapshot()
    #expect(snap.map(\.name) == ["c.txt", "b.txt"])
    await c.remove(at: 0)
    #expect(await c.snapshot().map(\.name) == ["b.txt"])
    await c.clear()
    #expect(await c.snapshot().isEmpty)      // clear empties the shelf
    #expect(FileShelfModule.shortPath("/Users/me/deep/dir/file.txt") == "…/dir/file.txt")
    #expect(FileShelfModule.shortPath("/a") == "/a")
}

@Test func fileShelfRowsAndEmptyState() {
    let m = FileShelfModule(controller: FileShelfController())
    let rows = m.detail(for: ShelfState(items: [ShelfItem(path: "/x/y.txt", name: "y.txt")]))
    #expect(rows[0].action == "shelf.open:0")
    #expect(rows[0].secondaryAction == "shelf.remove:0")   // per-file remove
    #expect(rows[0].title == "y.txt")
    // Empty shows guidance, no action.
    #expect(m.detail(for: .empty)[0].action == nil)
    #expect(m.face(for: ShelfState(items: [ShelfItem(path: "/x", name: "x")]), in: .rightPill).text == "1")
}

// MARK: - Calendar

private struct FakeCalendar: CalendarReading {
    let event: NextEvent?
    let access: Bool
    func requestAccess() async -> Bool { access }
    func nextEvent(from: Date, within seconds: TimeInterval) async -> NextEvent? { event }
}

@Test func calendarCountdownFormats() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(CalendarModule.countdown(to: now.addingTimeInterval(8 * 60), now: now) == "in 8m")
    #expect(CalendarModule.countdown(to: now.addingTimeInterval(2 * 3600 + 5 * 60), now: now) == "in 2h 5m")
    #expect(CalendarModule.countdown(to: now.addingTimeInterval(10), now: now) == "now")
    #expect(CalendarModule.countdown(to: now.addingTimeInterval(-180), now: now) == "started 3m ago")
}

@Test func calendarFaceReflectsImminence() {
    let m = CalendarModule(reader: FakeCalendar(event: nil, access: true))
    #expect(m.face(for: .none, in: .rightPill).text == "clear")
    let soon = NextEvent(title: "Standup", startsAt: Date().addingTimeInterval(3 * 60), isAllDay: false)
    #expect(m.face(for: soon, in: .rightPill).tint == .warning)   // ≤5 min → amber
    let later = NextEvent(title: "Review", startsAt: Date().addingTimeInterval(60 * 60), isAllDay: false)
    #expect(m.face(for: later, in: .rightPill).tint == .info)
    #expect(m.detail(for: later)[0].title == "Review")
}

// Minimal doubles so GitHub-backed modules can be built without a network.
import PerchGitHub
private struct NoopHTTP: HTTPClient {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse { HTTPResponse(status: 0, body: .init()) }
}
private struct NoopStore: TokenStore {
    func load() throws -> GitHubToken? { nil }
    func save(_ token: GitHubToken) throws {}
    func clear() throws {}
}
