import Foundation
import PerchCore

/// The dependencies the app hands a module when it starts.
///
/// Everything a module needs to do its job arrives here (rather than being
/// reached for globally), which is what makes modules injectable and testable.
/// It grows as the platform grows — a network client, a secret store, a logger —
/// without changing the module protocol.
public struct ModuleContext: Sendable {
    /// Injected clock so freshness/TTL logic is deterministic in tests.
    public let clock: any Clock
    /// The module's own persisted settings, already scoped to this module.
    public let settings: [String: String]

    public init(clock: any Clock = SystemClock(), settings: [String: String] = [:]) {
        self.clock = clock
        self.settings = settings
    }
}
