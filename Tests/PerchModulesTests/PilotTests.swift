import Testing
import Foundation
import PerchCore
import PerchModuleKit
@testable import PerchModules

// Pilot is deterministic: the ranker, the reducer, and the pill/panel mappings are
// pure functions, so they're worth pinning exactly.

private func action(_ id: String, _ priority: PilotPriority, url: String? = nil, tint: Tint = .neutral) -> PilotAction {
    PilotAction(id: id, title: id, symbolName: nil, tint: tint, priority: priority, url: url)
}

// MARK: - Ranker

@Test func rankerOrdersByPriorityThenStableId() {
    let ranked = PilotRanker.rank([
        action("b", .degraded, url: "u-b"),
        action("a", .prodDown, url: "u-a"),
        action("c", .readyToMerge, url: "u-c"),
    ])
    #expect(ranked.map(\.id) == ["a", "b", "c"])   // prodDown > degraded > readyToMerge
    let tie = PilotRanker.rank([action("z", .reviewAsked, url: "z"), action("a", .reviewAsked, url: "a")])
    #expect(tie.map(\.id) == ["a", "z"])           // same priority → stable by id, never flaps
}

@Test func rankerDedupsByUrlKeepingHighestPriority() {
    let ranked = PilotRanker.rank([
        action("low", .readyToMerge, url: "https://x/pr/1"),
        action("high", .conflicts, url: "https://x/pr/1"),
    ])
    #expect(ranked.count == 1)
    #expect(ranked[0].id == "high")
}

@Test func rankerDoesNotCollapseUrllessActions() {
    let ranked = PilotRanker.rank([action("a", .conflicts), action("b", .conflicts, url: "")])
    #expect(ranked.count == 2)
}

// MARK: - Reducer (the riskiest logic — reported / unavailable / retention)

private func src(_ name: String, renders: Int = 0, latest: Freshness = .unknown,
                 actions: [PilotAction] = []) -> PilotModule.SourceState {
    PilotModule.SourceState(name: name, renders: renders, latest: latest, lastActions: actions)
}

@Test func reduceStaysUnreadyUntilEverySourceReports() {
    // Seed only: one render each, still .unknown → not reported → Checking.
    let s = PilotModule.reduce([src("A", renders: 1), src("B", renders: 1)], unconfigured: [])
    #expect(s.ready == false)
    #expect(s.actions.isEmpty)
}

@Test func reduceTreatsPermanentUnknownAsReportedButUnavailable() {
    // A no-access repo stays .unknown; after its 2nd render it counts as reported
    // (so it can't pin Pilot at Checking) but is flagged unavailable.
    let s = PilotModule.reduce([src("A", renders: 2, latest: .unknown)], unconfigured: [])
    #expect(s.ready == true)
    #expect(s.sourcesUnavailable == ["A"])
}

@Test func reduceRetainsLastActionsWhenASourceGoesStale() {
    let kept = [action("keep", .conflicts, url: "u")]
    let s = PilotModule.reduce([src("A", renders: 2, latest: .stale(since: Date()), actions: kept)], unconfigured: [])
    #expect(s.actions.map(\.id) == ["keep"])      // retained across the blip
    #expect(s.sourcesUnavailable == ["A"])        // but honestly flagged
    #expect(s.ready == true)
}

@Test func reduceErrorBeforeAnyLiveIsReportedUnavailableWithNoActions() {
    let s = PilotModule.reduce([src("A", renders: 1, latest: .error("boom"))], unconfigured: [])
    #expect(s.ready == true)
    #expect(s.sourcesUnavailable == ["A"])
    #expect(s.actions.isEmpty)
}

@Test func reduceComputingIsNeutralNotUnavailable() {
    let a = [action("x", .readyToMerge, url: "u")]
    let s = PilotModule.reduce([src("A", renders: 2, latest: .computing, actions: a)], unconfigured: [])
    #expect(s.sourcesUnavailable.isEmpty)         // .computing isn't "unavailable"
    #expect(s.actions.map(\.id) == ["x"])
}

@Test func reduceFoldsUnconfiguredSourcesIntoUnavailable() {
    // A source turned on but not set up (CI with no repo) is unavailable, so Pilot
    // never says "All clear" while silently watching nothing.
    let s = PilotModule.reduce([src("My PRs", renders: 2, latest: .live)], unconfigured: ["Build"])
    #expect(s.sourcesUnavailable == ["Build"])
    #expect(s.ready == true)
}

// MARK: - Pill / panel

@Test func pilotFaceIsHonestAboutReadinessAndSources() {
    let m = PilotModule(members: [])
    let checking = m.face(for: PilotState(actions: [], sourcesUnavailable: [], ready: false), in: .panel)
    #expect(checking.text == "Checking…")
    let clear = m.face(for: PilotState(actions: [], sourcesUnavailable: [], ready: true), in: .panel)
    #expect(clear.text == "All clear")
    #expect(clear.tint == .good)
    let partial = m.face(for: PilotState(actions: [], sourcesUnavailable: ["Build"], ready: true), in: .panel)
    #expect(partial.text.contains("unavailable"))
    #expect(partial.tint != .good)
}

@Test func pilotFaceShowsTopActionAndCalmBadge() {
    let m = PilotModule(members: [])
    let top = PilotAction(id: "pr-review:o/r#2", title: "Review #2", tint: .warning, priority: .reviewAsked, url: "u2")
    let second = PilotAction(id: "pr-merge:o/r#1", title: "Merge #1", tint: .good, priority: .readyToMerge, url: "u1")
    let face = m.face(for: PilotState(actions: [top, second], sourcesUnavailable: [], ready: true), in: .panel)
    #expect(face.text == "Review #2 +1")
    #expect(face.tint == .warning)
    #expect(face.badge == .warning)            // attention dot because a warning is present
    // A calm, all-good top action paints NO alarm dot.
    let calm = m.face(for: PilotState(actions: [second], sourcesUnavailable: [], ready: true), in: .panel)
    #expect(calm.badge == nil)
}

@Test func pilotDetailListsActionsThenUnavailableSources() {
    let m = PilotModule(members: [])
    let a = PilotAction(id: "pr-merge:o/r#1", title: "Merge #1", tint: .good, priority: .readyToMerge, url: "u1")
    let rows = m.detail(for: PilotState(actions: [a], sourcesUnavailable: ["Deploy"], ready: true))
    #expect(rows.count == 2)
    #expect(rows[0].url == "u1")
    #expect(rows[1].title.contains("Deploy"))
    let clear = m.detail(for: PilotState(actions: [], sourcesUnavailable: [], ready: true))
    #expect(clear.count == 1)
    #expect(clear[0].title == "All clear")
}

@Test func pilotContextLabelCountsEnabledSources() {
    let m = PilotModule(members: [])
    // Defaults: My PRs + Reviews on, Builds + Deploy off → 2 sources.
    #expect(m.contextLabel(ModuleContext(settings: ["repo": "o/r"])) == "2 sources · o/r")
    // Turning on Builds adds a source; blank repo reads as "all repos".
    #expect(m.contextLabel(ModuleContext(settings: ["incBuilds": "true"])) == "3 sources · all repos")
}

// MARK: - Deploy actions

@Test func deployActionsMapHealthToPriority() {
    let m = DeployModule()
    let ctx = ModuleContext(settings: ["url": "https://api.example.com/health"])
    #expect(m.actions(for: .down, context: ctx).first?.priority == .prodDown)
    #expect(m.actions(for: .degraded, context: ctx).first?.priority == .degraded)
    #expect(m.actions(for: .healthy, context: ctx).isEmpty)
    #expect(m.actions(for: .down, context: ModuleContext()).isEmpty)          // no url → nothing
    #expect(m.actions(for: .down, context: ctx).first?.url == "https://api.example.com/health")
}

// MARK: - AnyNotchModule threads actions through to ModuleRender

private struct FakeActionModule: NotchModule {
    typealias State = Int
    static let descriptor = ModuleDescriptor(id: "fake.act", name: "Fake", summary: "",
                                             supportedSlots: [.panel], requiresConnection: false)
    func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Int>> {
        AsyncStream { cont in
            cont.yield(Snapshot(value: 1, freshness: .live, asOf: context.clock.now()))
            cont.finish()
        }
    }
    func face(for value: Int, in slot: Slot) -> PillFace { PillFace(text: "\(value)") }
    func actions(for value: Int, context: ModuleContext) -> [PilotAction] {
        [PilotAction(id: "fa-\(value)", title: "do", priority: .readyToMerge, url: "u")]
    }
}

@Test func anyNotchModuleThreadsActionsOntoRender() async {
    let any = AnyNotchModule(FakeActionModule())
    for await render in any.renderStream(ModuleContext(), slot: .panel) {
        #expect(render.actions.map(\.id) == ["fa-1"])
        break
    }
}
