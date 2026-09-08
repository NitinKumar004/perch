import Foundation
import PerchCore
import PerchModuleKit

/// A user-built combination: several glanceable modules merged into one pill and
/// one panel block. You tick which metrics to include (CPU, memory, thermal, …);
/// this runs those modules and folds their output together — the pill shows their
/// values joined ("CPU 27% · RAM 61%") with the worst-of colour, and the panel
/// shows each as its own row. Purely additive: it composes existing modules, it
/// doesn't change any of them.
public struct CombinedModule: NotchModule {
    public typealias State = [ModuleRender]   // latest render from each member, in order

    public static let descriptor = ModuleDescriptor(
        id: "system.combined",
        name: "Combined",
        summary: "Several system metrics in one — CPU, memory and more at a glance.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let members: [AnyNotchModule]

    /// - Parameter members: the sub-modules to fold together (built by the factory
    ///   from the include-toggles). An empty list yields a quiet placeholder.
    public init(members: [AnyNotchModule]) {
        self.members = members
    }

    /// The glanceable modules that can be combined, with their include-toggle key
    /// and default. Single source for both the factory and the catalog toggles —
    /// list modules (PRs, clipboard…) are intentionally absent: they can't fold
    /// into one pill value.
    public static func combinable() -> [(id: String, key: String, label: String, on: Bool)] {
        [
            ("system.cpu",     "incCPU",     "Include CPU",     true),
            ("system.memory",  "incMemory",  "Include memory",  true),
            ("system.network", "incNetwork", "Include network", false),
            ("system.thermal", "incThermal", "Include thermal", false),
            ("system.swap",    "incSwap",    "Include swap",    false),
            ("system.load",    "incLoad",    "Include load",    false),
            ("system.disk",    "incDisk",    "Include disk",    false),
            ("system.battery", "incBattery", "Include battery", false),
            ("system.clock",   "incClock",   "Include clock",   false),
        ]
    }

    /// Which member module ids the settings enable, in display order.
    public static func enabledMemberIDs(from settings: [String: String]) -> [String] {
        combinable().compactMap { m in
            let raw = settings[m.key]
            let on = raw.map { $0 == "true" } ?? m.on
            return on ? m.id : nil
        }
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<[ModuleRender]>> {
        let clock = context.clock
        let members = self.members
        return AsyncStream { continuation in
            let acc = Accumulator(count: members.count)
            let task = Task {
                continuation.yield(Snapshot(value: [], freshness: .unknown, asOf: clock.now()))
                await withTaskGroup(of: Void.self) { group in
                    for (i, member) in members.enumerated() {
                        group.addTask {
                            // slot-independent face — merged pill looks the same wherever it sits
                            for await render in member.renderStream(context, slot: .panel) {
                                let (merged, allReported) = await acc.update(index: i, render: render)
                                // Stay `.unknown` until EVERY member has reported at
                                // least once. Otherwise the first member to arrive
                                // makes a partial pill look `.live`, consuming the
                                // "first live = silent baseline" slot — so a second
                                // member that's already-critical-at-launch would
                                // wrongly fire an auto-open instead of being adopted
                                // as baseline.
                                let freshness: Freshness = allReported ? .live : .unknown
                                continuation.yield(Snapshot(value: merged, freshness: freshness, asOf: clock.now()))
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: [ModuleRender], in slot: Slot) -> PillFace {
        Self.mergedFace(value)
    }

    public func detail(for value: [ModuleRender]) -> [DetailRow] {
        // Each member contributes its own rows → a mini system dashboard.
        value.flatMap { $0.detail }
    }

    public func notification(for value: [ModuleRender], previous: [ModuleRender]?) -> ModuleAlert? {
        // Forward a member's alert (e.g. thermal went hot). The notifier dedups
        // by id, so a persisted rising-edge render can't nag twice.
        value.compactMap { $0.alert }.first
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let n = Self.enabledMemberIDs(from: context.settings).count
        return n == 0 ? "nothing selected" : "\(n) metric\(n == 1 ? "" : "s")"
    }

    /// Merge member pill faces. Each metric keeps its OWN colour via `segments`;
    /// `text`/`tint` stay the single-colour fallback (worst-of), used by the
    /// menu-bar status icon and anything that can't render segments.
    static func mergedFace(_ renders: [ModuleRender]) -> PillFace {
        guard !renders.isEmpty else {
            return PillFace(text: "—", symbolName: "square.stack.3d.up", tint: .neutral,
                            tooltip: "No metrics selected")
        }
        // Each member becomes a segment: text for a normal metric, or a small
        // BAR for a bar-only member (e.g. thermal pressure). In a menu-bar pill
        // the flank is only ~400pt wide, so with many members enabled (up to 9)
        // the run would overflow and hard-clip. Keep the leading members that fit
        // a width budget and add a trailing "…" — colour/attention still reflect
        // ALL members (below), and the panel lists every one, so nothing is lost.
        let allSegments = renders.map { r in
            FaceSegment(text: r.pill.face.text, tint: r.pill.face.tint, progress: r.pill.face.progress)
        }
        let (shown, truncated) = fitSegments(allSegments)
        let segments = truncated ? shown + [FaceSegment(text: "…", tint: .neutral)] : shown
        // The fallback single-colour text uses only the shown, labelled members;
        // the "· …" suffix matches the separator the segment path draws before
        // its own "…" segment, so both render the truncation the same way.
        let text = shown.compactMap { $0.text.isEmpty ? nil : $0.text }
            .joined(separator: " · ") + (truncated ? " · …" : "")
        let tint = worstTint(renders.map { $0.pill.face.tint })
        // If any member wants attention, surface one dot in the worst member tint.
        let badges = renders.compactMap { $0.pill.face.badge }
        let badge = badges.isEmpty ? nil : worstTint(badges)
        return PillFace(text: text, symbolName: nil, tint: tint,
                        tooltip: renders.map { $0.pill.face.tooltip ?? $0.pill.face.text }.joined(separator: " · "),
                        segments: segments, badge: badge)
    }

    /// Widest a combined pill may get, in monospace character-units (~6.6pt each).
    /// ~44 keeps it inside one notch flank (~400pt) with margin.
    static let pillCharBudget = 44

    /// Keep the leading segments whose combined width fits `pillCharBudget`, and
    /// report whether any were dropped. Always keeps at least the first member
    /// (a lone very-wide member is clamped by the view, never blanked). A bar
    /// member counts ~3 chars; the "·" separator ~2.
    static func fitSegments(_ segments: [FaceSegment]) -> (shown: [FaceSegment], truncated: Bool) {
        var used = 0
        var shown: [FaceSegment] = []
        for seg in segments {
            let w = seg.progress != nil ? 3 : seg.text.count
            let sep = shown.isEmpty ? 0 : 2
            if !shown.isEmpty, used + sep + w > pillCharBudget { return (shown, true) }
            used += sep + w
            shown.append(seg)
        }
        return (shown, false)
    }

    /// The most alarming tint present, so one red metric turns the whole pill red.
    static func worstTint(_ tints: [Tint]) -> Tint {
        func rank(_ t: Tint) -> Int {
            switch t {
            case .neutral: return 0
            case .good:    return 1
            case .info:    return 2
            case .accent:  return 2
            case .warning: return 3
            case .critical:return 4
            }
        }
        return tints.max(by: { rank($0) < rank($1) }) ?? .neutral
    }
}

/// Collects the latest render from each member and returns the ordered list plus
/// whether EVERY member has now reported at least once (so the stream can hold
/// `.unknown` until the combined pill is fully populated).
private actor Accumulator {
    private var latest: [ModuleRender?]
    init(count: Int) { latest = Array(repeating: nil, count: count) }
    func update(index: Int, render: ModuleRender) -> (merged: [ModuleRender], allReported: Bool) {
        if latest.indices.contains(index) { latest[index] = render }
        let merged = latest.compactMap { $0 }
        return (merged, merged.count == latest.count)
    }
}
