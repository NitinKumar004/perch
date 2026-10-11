import Foundation
import PerchCore
import PerchModuleKit

/// Pilot — "turn the glance into the next move". A deterministic aggregator (no
/// AI): it composes the actionable dev-signal modules (your PRs, review-requested
/// PRs, Builds, Deploy), collects the `PilotAction`s each one derives from its own
/// typed state, ranks them on one shared priority scale, and surfaces the single
/// highest-leverage next action on the pill plus the ranked list (each tappable) in
/// the panel. Purely additive: it runs existing modules, changing none of them.
public struct PilotModule: NotchModule {
    public typealias State = PilotState

    public static let descriptor = ModuleDescriptor(
        id: "pilot.actions",
        name: "Pilot",
        summary: "Your single highest-leverage next action, across PRs, CI and deploys.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: true,
        detailFirst: true,
        // Pilot is a to-do list, not a live incident siren — it colours the pill but
        // never force-opens the panel (the member modules already alert on their own
        // transitions; Pilot raises no notifications of its own).
        opensPanelOnCritical: false
    )

    /// The signal sources Pilot can compose, with their include-toggle key, label
    /// and default. Single source of truth for the settings list, the factory's
    /// include-logic and `contextLabel` — so a default can't drift across the three.
    public static func sources() -> [(key: String, label: String, on: Bool)] {
        // PRs/reviews work with zero config (all accessible repos). Builds + deploy
        // need a repo / URL, so they default OFF — a fresh Pilot is immediately
        // useful and clean ("All clear"), not "1 unavailable" until you set a repo.
        [("incMyPRs",  "Include my PRs",          true),
         ("incReviews", "Include review requests", true),
         ("incBuilds",  "Include CI builds",       false),
         ("incDeploy",  "Include deploy health",   false)]
    }

    /// One composed signal source: a built module plus the settings its stream
    /// should read (passed as a per-member `ModuleContext`), plus a human name used
    /// when that source is unavailable.
    public struct Member: Sendable {
        public let module: AnyNotchModule
        public let settings: [String: String]
        public let name: String
        public init(module: AnyNotchModule, settings: [String: String], name: String) {
            self.module = module
            self.settings = settings
            self.name = name
        }
    }

    private let members: [Member]
    /// Names of sources the user turned on but didn't finish configuring (e.g. CI
    /// with no repo). They can't produce actions, so they're reported as unavailable
    /// — otherwise Pilot would say "All clear" while silently watching nothing.
    private let unconfigured: [String]

    public init(members: [Member], unconfigured: [String] = []) {
        self.members = members
        self.unconfigured = unconfigured
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<PilotState>> {
        let clock = context.clock
        let members = self.members
        let unconfigured = self.unconfigured
        return AsyncStream { continuation in
            // Seed so the panel isn't blank and the pill reads "Checking…" (not a
            // premature "All clear") until every source has reported.
            let seed = Self.reduce(members.map { SourceState(name: $0.name) }, unconfigured: unconfigured)
            continuation.yield(Snapshot(value: seed, freshness: seed.ready ? .live : .unknown, asOf: clock.now()))

            let acc = PilotAccumulator(names: members.map(\.name), unconfigured: unconfigured,
                                       continuation: continuation, clock: clock)
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for (i, member) in members.enumerated() {
                        group.addTask {
                            let ctx = ModuleContext(clock: clock, settings: member.settings)
                            for await render in member.module.renderStream(ctx, slot: .panel) {
                                await acc.update(index: i, render: render)
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: PilotState, in slot: Slot) -> PillFace {
        guard value.ready else {
            return PillFace(text: "Checking…", symbolName: "hourglass", tint: .neutral,
                            tooltip: "Pilot is gathering signals")
        }
        let unavailable = value.sourcesUnavailable
        if value.actions.isEmpty {
            if unavailable.isEmpty {
                return PillFace(text: "All clear", symbolName: "checkmark.seal", tint: .good,
                                tooltip: "Nothing needs you right now")
            }
            return PillFace(text: "\(unavailable.count) unavailable", symbolName: "wifi.exclamationmark",
                            tint: .neutral, tooltip: "No actions · unavailable: \(unavailable.joined(separator: ", "))")
        }
        let top = value.actions[0]
        let more = value.actions.count - 1
        let text = more > 0 ? "\(top.title) +\(more)" : top.title
        let note = unavailable.isEmpty ? "" : "  ·  \(unavailable.count) source\(unavailable.count == 1 ? "" : "s") unavailable"
        // Attention dot only when something actually wants attention (warning/critical),
        // so a calm "ready to merge" top action doesn't paint an alarm.
        let worst = CombinedModule.worstTint(value.actions.map(\.tint))
        let badge: Tint? = (worst == .warning || worst == .critical) ? worst : nil
        return PillFace(text: text, symbolName: top.symbolName, tint: top.tint,
                        tooltip: "\(top.title)\(top.subtitle.map { " — \($0)" } ?? "")\(note)",
                        badge: badge)
    }

    public func detail(for value: PilotState) -> [DetailRow] {
        var rows = value.actions.map { a in
            DetailRow(id: a.id, title: a.title, subtitle: a.subtitle, tint: a.tint,
                      symbolName: a.symbolName, url: a.url)
        }
        for name in value.sourcesUnavailable {
            rows.append(DetailRow(id: "pilot-unavailable-\(name)", title: "\(name) unavailable",
                                  subtitle: "signal not available", tint: .warning,
                                  symbolName: "wifi.exclamationmark"))
        }
        if rows.isEmpty, value.ready {
            rows = [DetailRow(id: "pilot-clear", title: "All clear",
                              subtitle: "Nothing needs you right now", tint: .good, symbolName: "checkmark.seal")]
        }
        return rows
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let count = Self.sources().filter { context.bool($0.key, fallback: $0.on) }.count
        let repo = (context.settings["repo"].flatMap { $0.isEmpty ? nil : $0 }) ?? "all repos"
        return "\(count) source\(count == 1 ? "" : "s") · \(repo)"
    }

    // MARK: - Pure reduction (testable)

    /// One source's accumulated view, as the reducer sees it.
    struct SourceState: Sendable {
        var name: String
        var renders = 0
        var latest: Freshness = .unknown
        var lastActions: [PilotAction] = []
    }

    /// Fold the per-source states (+ any configured-but-unbuilt sources) into one
    /// `PilotState`. Pure and deterministic — the riskiest logic, kept out of the
    /// actor so it can be table-tested.
    static func reduce(_ sources: [SourceState], unconfigured: [String]) -> PilotState {
        // reported = produced a real render beyond the initial `.unknown` seed:
        // latest is no longer `.unknown`, OR it has emitted ≥2 renders (covers a
        // source that stays `.unknown`, e.g. a no-access repo, so one bad source
        // doesn't pin Pilot at "Checking…" forever).
        func reported(_ s: SourceState) -> Bool { s.latest != .unknown || s.renders >= 2 }
        let allReported = sources.allSatisfy(reported)

        // A reported source whose latest render isn't usable is "unavailable".
        // `.computing` is neutral — keep its retained actions, don't count it.
        var unavailable: [String] = sources.compactMap { s in
            guard reported(s) else { return nil }
            switch s.latest {
            case .live, .computing: return nil
            case .stale, .error, .unknown: return s.name
            }
        }
        unavailable += unconfigured   // turned on but not set up → always unavailable

        let ranked = PilotRanker.rank(sources.flatMap { $0.lastActions })
        return PilotState(actions: ranked, sourcesUnavailable: unavailable, ready: allReported)
    }
}

/// Pure, deterministic ranking of Pilot actions. No clock, no randomness.
public enum PilotRanker {
    public static func rank(_ actions: [PilotAction]) -> [PilotAction] {
        // Dedup by non-empty url (two sources pointing at the same place → keep the
        // more urgent one). Url-less actions never collapse together.
        var byURL: [String: PilotAction] = [:]
        var urlless: [PilotAction] = []
        for a in actions {
            guard let u = a.url, !u.isEmpty else { urlless.append(a); continue }
            if let existing = byURL[u] {
                if a.priority > existing.priority { byURL[u] = a }
            } else {
                byURL[u] = a
            }
        }
        let merged = Array(byURL.values) + urlless
        // Priority desc, then stable tie-break by id so order never flaps between polls.
        return merged.sorted { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority > rhs.priority : lhs.id < rhs.id
        }
    }
}

/// Collects the latest render from each member and OWNS the continuation so every
/// emission happens inside the actor — serialized and in arrival order, with no
/// `await` between the state mutation and the synchronous `yield`. That removes the
/// interleaving race a yield-outside-the-actor design would have.
private actor PilotAccumulator {
    private var sources: [PilotModule.SourceState]
    private let unconfigured: [String]
    private let continuation: AsyncStream<Snapshot<PilotState>>.Continuation
    private let clock: any Clock

    init(names: [String], unconfigured: [String],
         continuation: AsyncStream<Snapshot<PilotState>>.Continuation, clock: any Clock) {
        self.sources = names.map { PilotModule.SourceState(name: $0) }
        self.unconfigured = unconfigured
        self.continuation = continuation
        self.clock = clock
    }

    func update(index: Int, render: ModuleRender) {
        guard sources.indices.contains(index) else { return }
        sources[index].renders += 1
        sources[index].latest = render.pill.freshness
        if render.pill.freshness.isTrustworthy { sources[index].lastActions = render.actions }
        let state = PilotModule.reduce(sources, unconfigured: unconfigured)
        continuation.yield(Snapshot(value: state, freshness: state.ready ? .live : .unknown, asOf: clock.now()))
    }
}
