import Foundation
import PerchCore

/// How urgent one `PilotAction` is — the single ranking axis every module shares,
/// so Pilot can merge actions from different signals and sort them consistently.
///
/// The named levels are the ONLY way to make a priority: the memberwise init is
/// internal, so a module in `PerchModules` picks a documented level rather than
/// inventing a magic number. Higher `rank` = more urgent.
public struct PilotPriority: Comparable, Hashable, Sendable {
    public let rank: Int
    init(_ rank: Int) { self.rank = rank }

    public static func < (lhs: PilotPriority, rhs: PilotPriority) -> Bool { lhs.rank < rhs.rank }

    /// A deploy/health endpoint is down — a production incident, nothing outranks it.
    public static let prodDown      = PilotPriority(100)
    /// CI failing on a *specific* branch you chose to watch (your main build is broken).
    public static let mainBroken    = PilotPriority(90)
    /// Deploy degraded (reachable but non-2xx) — still an incident, so above your own work.
    public static let degraded      = PilotPriority(80)
    /// Changes requested on YOUR PR with unresolved threads — the ball is in your court.
    public static let yourMove      = PilotPriority(70)
    /// Your PR has merge conflicts — blocks landing it.
    public static let conflicts     = PilotPriority(68)
    /// CI failing on your PR, or a watched build on any/unspecified branch.
    public static let ciFailingPR   = PilotPriority(65)
    /// A review has been requested of you — unblocking someone else ranks above landing
    /// your own already-green PR (a deliberate call; flip the two if you disagree).
    public static let reviewAsked   = PilotPriority(55)
    /// Your PR is approved + green + mergeable — a win that's ready to land.
    public static let readyToMerge  = PilotPriority(50)
}

/// One suggested next action Pilot surfaces: what to do, how urgent, and where a
/// tap goes. In v1 every action is *navigation* — opening the thing in the
/// browser — so `url` is the whole interaction; write-actions (merge, re-run) are
/// a v2 concern layered on later.
public struct PilotAction: Equatable, Sendable, Identifiable {
    /// Stable, per-kind-prefixed dedup key, e.g. `"pr-merge:owner/repo#120"`. The
    /// same action across polls keeps the same id, so ordering never flaps and the
    /// shell can dedup.
    public let id: String
    public let title: String
    public let subtitle: String?
    public let symbolName: String?
    public let tint: Tint
    public let priority: PilotPriority
    /// Where a tap opens (the PR, the failing run, the deploy). nil = no target.
    public let url: String?

    public init(id: String, title: String, subtitle: String? = nil,
                symbolName: String? = nil, tint: Tint = .neutral,
                priority: PilotPriority, url: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.tint = tint
        self.priority = priority
        self.url = url
    }
}

/// Pilot's typed state: the ranked actions plus enough about the *sources* to stay
/// honest on the pill. `face`/`detail` only receive `State` (never freshness), so
/// readiness and source availability are carried here — that's what lets the pill
/// say "Checking…" or "N unavailable" instead of a confident, wrong "All clear".
public struct PilotState: Equatable, Sendable {
    /// Already ranked (most urgent first).
    public let actions: [PilotAction]
    /// Human names of sources that are configured but whose signal isn't usable —
    /// either a reported render that's stale/error/no-access, or a source you turned
    /// on but haven't finished setting up (e.g. CI with no repo). Lets the pill +
    /// panel admit the picture is partial instead of a false "All clear".
    public let sourcesUnavailable: [String]
    /// True once every live source has reported at least once — until then the pill
    /// reads "Checking…" rather than a premature "All clear".
    public let ready: Bool

    public init(actions: [PilotAction], sourcesUnavailable: [String], ready: Bool) {
        self.actions = actions
        self.sourcesUnavailable = sourcesUnavailable
        self.ready = ready
    }

    public static let empty = PilotState(actions: [], sourcesUnavailable: [], ready: false)
}
