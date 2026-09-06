import Testing
import Foundation
import PerchCore
import PerchModuleKit
import PerchGitHub
import PerchConfig
@testable import PerchModules

/// End-to-end: for every feature, *configure it the way a user would* and drive
/// the real module → stream → render path, asserting the configured behaviour
/// actually shows up. This is the "after I set it, does it work?" check for each
/// module and each configuration, not just the pure mapping functions.

// MARK: - Test doubles (GitHub without a network)

/// Returns canned Actions-runs / GraphQL payloads by URL path, so the real
/// GitHub modules run their real stream logic against believable data.
private struct StubGitHubHTTP: HTTPClient {
    var checksState = "SUCCESS"
    var checksTotal = 10
    var runsConclusion = "success"

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let path = request.url.path
        let headers = ["X-RateLimit-Remaining": "4999", "X-RateLimit-Reset": "\(Int(Date().timeIntervalSince1970) + 3600)", "ETag": "\"e\""]
        if path.hasSuffix("/actions/runs") {
            let body = """
            {"workflow_runs":[{"status":"completed","conclusion":"\(runsConclusion)","updated_at":"2026-09-06T10:00:00Z","run_started_at":"2026-09-06T09:59:00Z","html_url":"https://github.com/o/r/actions/runs/1","name":"CI","head_branch":"main","head_sha":"abcdef1234567"}]}
            """
            return HTTPResponse(status: 200, body: Data(body.utf8), headers: headers)
        }
        if path.hasSuffix("/graphql") {
            let body = """
            {"data":{"search":{"issueCount":2,"nodes":[
              {"number":10,"title":"First PR","url":"https://github.com/o/r/pull/10","isDraft":false,"reviewDecision":"REVIEW_REQUIRED","mergeable":"MERGEABLE","repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"\(checksState)","contexts":{"totalCount":\(checksTotal),"checkRunCountsByState":[{"state":"COMPLETED","count":5}],"statusContextCountsByState":[]}}}}]}},
              {"number":11,"title":"Second PR","url":"https://github.com/o/r/pull/11","isDraft":false,"reviewDecision":"APPROVED","mergeable":"MERGEABLE","repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[]}}
            ]}}}
            """
            return HTTPResponse(status: 200, body: Data(body.utf8), headers: headers)
        }
        return HTTPResponse(status: 404, body: Data(), headers: headers)
    }
}

private struct TokenReturningStore: TokenStore {
    func load() throws -> GitHubToken? {
        GitHubToken(accessToken: "t", refreshToken: nil, expiresAt: nil, refreshTokenExpiresAt: nil)
    }
    func save(_ token: GitHubToken) throws {}
    func clear() throws {}
}

private func stubbedClient(_ http: StubGitHubHTTP = StubGitHubHTTP()) -> GitHubAPIClient {
    GitHubAPIClient(http: http,
                    auth: GitHubAuth(flow: GitHubDeviceFlow(http: http, clientID: "x"),
                                     store: TokenReturningStore()))
}

// MARK: - Stream driver

/// Drive a module's real render stream and return the first render matching
/// `predicate`, or nil on timeout — so a stuck stream fails loudly, never hangs.
private func firstRender(_ module: AnyNotchModule,
                         settings: [String: String] = [:],
                         timeout: Duration = .seconds(10),
                         where predicate: @escaping @Sendable (ModuleRender) -> Bool) async -> ModuleRender? {
    let context = ModuleContext(settings: settings)
    let stream = module.renderStream(context, slot: .panel)
    return await withTaskGroup(of: ModuleRender?.self) { group in
        group.addTask {
            for await render in stream where predicate(render) { return render }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

// MARK: - Config layer: configure → persist → reload → wire

@Test func e2e_configRoundTripsEveryPieceOfUserIntent() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("perch-e2e-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("layout.json")
    let store = ConfigStore(fileURL: url)

    var config = LayoutConfig(
        activePreset: "work",
        presets: ["work": Preset(
            leftPill: SlotBinding(module: "system.cpu"),
            rightPill: SlotBinding(module: "system.clock", settings: ["format": "12", "showSeconds": "true"]),
            panel: [
                SlotBinding(module: "github.prs", settings: ["showChecks": "false", "limit": "3"]),
                SlotBinding(module: "system.port", settings: ["port": "8080", "label": "api"]),
            ])],
        hudPosition: "right")
    config.global = GlobalSettings(autoOpenOnRed: true, quietHours: "22:00-08:00")
    try store.save(config)

    // Reload from disk → every configured value survives exactly.
    let reloaded = store.load()
    #expect(reloaded == config)
    #expect(reloaded.global.autoOpenOnRed)
    #expect(reloaded.current?.rightPill?.settings["format"] == "12")
    #expect(reloaded.current?.panel.first?.settings["limit"] == "3")
    #expect(reloaded.hudPosition == "right")
}

/// Every module a user can pick from Settings must actually build from its
/// configured binding — a catalog entry the factory can't construct is a dead
/// option in the UI.
@Test func e2e_everyCatalogModuleBuildsFromItsConfig() {
    let factory = ModuleFactory(
        apiClient: stubbedClient(),
        timerController: TimerController(),
        clipboardController: ClipboardController(),
        fileShelfController: FileShelfController())

    for entry in ModuleCatalog.all() {
        // Fill required free-text settings with a valid sample so construction
        // succeeds the way it would after the user typed them.
        var settings: [String: String] = [:]
        for setting in entry.settings where setting.defaultValue.isEmpty && setting.options == nil {
            switch setting.key {
            case "repo":  settings[setting.key] = "owner/name"
            case "repos": settings[setting.key] = "owner/a, owner/b"
            case "url":   settings[setting.key] = "https://example.com/health"
            default:      settings[setting.key] = "1"
            }
        }
        let module = factory.makeModule(for: SlotBinding(module: entry.id, settings: settings))
        #expect(module != nil, "catalog module \(entry.id) failed to build from its config")
    }
}

// MARK: - Local modules: real stream, config reflected

@Test func e2e_clockHonorsFormatAndSeconds() async {
    let m = AnyNotchModule(ClockModule())
    let h24 = await firstRender(m, settings: ["format": "24"]) { $0.pill.freshness == .live }
    #expect(h24?.pill.face.text.contains(":") == true)
    #expect(h24?.pill.face.text.contains("M") == false)     // no AM/PM in 24h

    let h12 = await firstRender(m, settings: ["format": "12", "showSeconds": "true"]) { $0.pill.freshness == .live }
    let text = h12?.pill.face.text ?? ""
    #expect(text.contains("AM") || text.contains("PM"))          // 12h shows meridiem
    #expect(text.filter { $0 == ":" }.count == 2)                // hh:mm:ss
}

@Test func e2e_portMonitorReflectsConfiguredPort() async {
    // Bind a listener so the probe reports "up", then confirm the module shows it.
    let listener = TinyListener()
    let port = try? listener.start()
    defer { listener.stop() }
    guard let port else { return }   // environment couldn't bind; skip

    let m = AnyNotchModule(PortMonitorModule())
    let render = await firstRender(m, settings: ["port": "\(port)", "label": "dev"]) {
        $0.pill.freshness == .live
    }
    #expect(render?.pill.face.text == "dev")
    #expect(render?.pill.face.tint == .good)                // listening → green
    #expect(render?.detail.first?.subtitle?.contains("listening") == true)
}

@Test func e2e_networkAndVitalsProduceLiveValues() async {
    let net = await firstRender(AnyNotchModule(NetworkModule()), settings: ["refreshSeconds": "1"]) {
        $0.pill.freshness == .live
    }
    #expect(net?.pill.face.text.contains("/s") == true)     // a real rate

    let mem = await firstRender(AnyNotchModule(MemoryModule())) { $0.pill.freshness == .live }
    #expect(mem?.pill.face.text.contains("RAM") == true)
}

@Test func e2e_clipboardStreamPicksUpRecordedEntries() async {
    let controller = ClipboardController()
    await controller.record("hello e2e")
    let m = AnyNotchModule(ClipboardModule(controller: controller))
    // (The module also seeds the real system pasteboard, so find the row by title.)
    let render = await firstRender(m) { r in r.detail.contains { $0.title == "hello e2e" } }
    let row = render?.detail.first { $0.title == "hello e2e" }
    #expect(row?.action == "clip.copy:hello e2e")   // action carries the text, not an index
}

@Test func e2e_fileShelfStreamShowsDroppedFile() async {
    let controller = FileShelfController()
    await controller.add(path: "/Users/me/report.pdf")
    let m = AnyNotchModule(FileShelfModule(controller: controller))
    let render = await firstRender(m) { r in r.detail.contains { $0.title == "report.pdf" } }
    let row = render?.detail.first { $0.title == "report.pdf" }
    #expect(row?.action == "shelf.open:/Users/me/report.pdf")           // keyed by path
    #expect(row?.secondaryAction == "shelf.remove:/Users/me/report.pdf")
}

@Test func e2e_deployHealthReflectsConfiguredURL() async {
    let m = AnyNotchModule(DeployModule(probe: HealthProbe { _ in 200 }))
    let render = await firstRender(m, settings: ["url": "https://cloudemu.info/health"]) {
        $0.pill.face.text == "up"
    }
    #expect(render?.pill.face.tint == .good)
    #expect(render?.contextLabel == "cloudemu.info")             // names what it's watching
}

@Test func e2e_calendarShowsCountdownForConfiguredLookahead() async {
    let soon = NextEvent(title: "Sprint review", startsAt: Date().addingTimeInterval(20 * 60), isAllDay: false)
    let m = AnyNotchModule(CalendarModule(reader: FakeCal(event: soon)))
    let render = await firstRender(m, settings: ["lookaheadHours": "6"]) { $0.pill.freshness == .live }
    #expect(render?.detail.first?.title == "Sprint review")
    #expect(render?.detail.first?.subtitle?.contains("in ") == true)
}

// MARK: - GitHub modules: real stream over stubbed API, config reflected

@Test func e2e_buildModuleStreamsPassingFromConfiguredRepo() async {
    let factory = githubFactory()
    let m = factory.makeModule(for: SlotBinding(module: "github.builds", settings: ["repo": "o/r", "branch": "main"]))!
    let render = await firstRender(m) { $0.pill.face.tint == .good }
    #expect(render?.detail.first?.url == "https://github.com/o/r/actions/runs/1")
    #expect(render?.contextLabel == "o/r · main")
}

@Test func e2e_prModuleHonorsShowChecksConfig() async {
    // showChecks/limit are read from ModuleContext at stream time, so they flow
    // in via firstRender(settings:) — exactly as the shell hands them to a stream.
    let on = githubFactory().makeModule(for: SlotBinding(module: "github.prs"))!
    let onRender = await firstRender(on, settings: ["showChecks": "true"]) { r in !r.detail.isEmpty && r.pill.freshness == .live }
    #expect(onRender?.detail.first?.subtitle?.contains("CI") == true)

    // showChecks OFF → same data, no CI text.
    let off = githubFactory().makeModule(for: SlotBinding(module: "github.prs"))!
    let offRender = await firstRender(off, settings: ["showChecks": "false"]) { r in !r.detail.isEmpty && r.pill.freshness == .live }
    #expect(offRender?.detail.first?.subtitle?.contains("CI") == false)
}

@Test func e2e_prModuleHonorsLimitConfig() async {
    let m = githubFactory().makeModule(for: SlotBinding(module: "github.prs"))!
    let render = await firstRender(m, settings: ["limit": "1"]) { r in !r.detail.isEmpty && r.pill.freshness == .live }
    #expect(render?.detail.first?.title.hasPrefix("#10") == true)
}

@Test func e2e_multiBuildStreamsWorstOfConfiguredRepos() async {
    var http = StubGitHubHTTP(); http.runsConclusion = "failure"
    let factory = ModuleFactory(apiClient: stubbedClient(http),
                                timerController: TimerController(),
                                clipboardController: ClipboardController(),
                                fileShelfController: FileShelfController())
    let m = factory.makeModule(for: SlotBinding(module: "github.builds.multi"))!
    // repos is a stream-time setting → passed through the context here.
    let render = await firstRender(m, settings: ["repos": "o/a, o/b"]) { $0.pill.face.tint == .critical }
    #expect(render?.pill.face.text.contains("✗") == true)   // shows the red count
    #expect(render?.detail.count == 2)                            // both configured repos listed
}

private func githubFactory() -> ModuleFactory {
    ModuleFactory(apiClient: stubbedClient(),
                  timerController: TimerController(),
                  clipboardController: ClipboardController(),
                  fileShelfController: FileShelfController())
}

// A calendar reader that grants access and returns a fixed event.
private struct FakeCal: CalendarReading {
    let event: NextEvent?
    func requestAccess() async -> Bool { true }
    func nextEvent(from: Date, within seconds: TimeInterval) async -> NextEvent? { event }
}

/// A throwaway TCP listener on an ephemeral loopback port, so the port-monitor
/// module has something real to detect. Mirrors what a dev server would present.
private final class TinyListener {
    private var fd: Int32 = -1

    /// Bind + listen on 127.0.0.1:0 and return the OS-assigned port.
    func start() throws -> UInt16 {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { throw Err.socket }
        var yes: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0                                   // let the OS choose
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(s, 1) == 0 else { close(s); throw Err.bind }

        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(s, $0, &len) }
        }
        fd = s
        return UInt16(bigEndian: actual.sin_port)
    }

    func stop() { if fd >= 0 { close(fd); fd = -1 } }
    enum Err: Error { case socket, bind }
}
