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

    /// The user-configured refresh interval in seconds, or `fallback` if unset,
    /// clamped to at least `minimum` so a typo can't hammer a source.
    public func refreshSeconds(fallback: Double, minimum: Double = 5) -> Double {
        guard let raw = settings["refreshSeconds"], let value = Double(raw) else { return fallback }
        return Swift.max(minimum, value)
    }

    /// A boolean setting stored as "true"/"false", or `fallback` if unset.
    public func bool(_ key: String, fallback: Bool) -> Bool {
        guard let raw = settings[key] else { return fallback }
        return raw == "true"
    }

    /// An integer setting, or `fallback` if unset/invalid, clamped to a range.
    public func int(_ key: String, fallback: Int, minimum: Int = 1, maximum: Int = 100) -> Int {
        guard let raw = settings[key], let value = Int(raw) else { return fallback }
        return Swift.min(maximum, Swift.max(minimum, value))
    }
}
