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
}

public extension NotchModule {
    func detail(for value: State) -> [DetailRow] { [] }
    func notification(for value: State, previous: State?) -> ModuleAlert? { nil }
}
