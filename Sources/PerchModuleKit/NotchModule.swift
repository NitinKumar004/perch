import Foundation
import PerchCore

/// The single contract every feature implements. A module is a *pure producer*
/// of typed state over time, plus a pure mapping from that state to a pill's
/// appearance. It knows nothing about how it is rendered or where its data is
/// stored — that is what keeps the system decoupled and extensible.
///
/// Adding a new signal to Perch means writing one `NotchModule`. No other layer
/// changes.
public protocol NotchModule: Sendable {
    /// The module's typed state (e.g. a build result, a `Date`, a PR list).
    associatedtype State: Sendable

    /// Static metadata: id, name, supported slots, whether it needs a connection.
    static var descriptor: ModuleDescriptor { get }

    /// Produce a stream of state snapshots. The module decides its own cadence
    /// (a timer, an event source, a one-shot). Cancellation of the stream must
    /// stop its work.
    func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<State>>

    /// Pure mapping from a state value to how the pill should look in `slot`.
    /// Called by the shell; must not have side effects.
    func face(for value: State, in slot: Slot) -> PillFace

    /// Pure mapping from a state value to the detail rows shown in the panel.
    /// Defaults to empty — a module only overrides this when it has more to show
    /// than its pill (e.g. a build's commit + open-run link, or a PR list).
    func detail(for value: State) -> [DetailRow]

    /// A notification to raise given the new state and the previous one, or nil.
    /// Defaults to nil — a module overrides it to alert on notable transitions
    /// (a build turning red, a new review request). The shell dedups by the
    /// alert's `id`, so returning the same alert repeatedly fires it once.
    func notification(for value: State, previous: State?) -> ModuleAlert?

    /// A short line naming what this module is watching (the repo, the URL host,
    /// …), shown under the panel row title. Receives the same context (settings)
    /// as `stream`, so it can name the configured repo/URL. Defaults to nil.
    func contextLabel(_ context: ModuleContext) -> String?

    /// Suggested next actions derived purely from this state (and the module's
    /// settings), for the Pilot aggregator to rank and surface. Defaults to empty —
    /// a module overrides it only when its state implies something to *do* (merge a
    /// ready PR, look at a failing run, check a down deploy). Takes `context` so a
    /// module can read its own settings (e.g. a URL that lives there, not in State),
    /// mirroring `contextLabel`.
    func actions(for value: State, context: ModuleContext) -> [PilotAction]
}

public extension NotchModule {
    func detail(for value: State) -> [DetailRow] { [] }
    func notification(for value: State, previous: State?) -> ModuleAlert? { nil }
    func contextLabel(_ context: ModuleContext) -> String? { nil }
    func actions(for value: State, context: ModuleContext) -> [PilotAction] { [] }
}
