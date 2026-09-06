import Foundation
import PerchCore
import PerchModuleKit

/// The system thermal state — the sanctioned "is my Mac overheating / about to
/// throttle" signal. macOS gives no public CPU-temperature reading on Apple
/// Silicon, but it does expose `ProcessInfo.thermalState`, which is exactly the
/// early warning you want before a heat-induced slowdown.
public enum ThermalLevel: Sendable, Equatable {
    case cool, warm, hot, critical

    static func from(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal:  return .cool
        case .fair:     return .warm
        case .serious:  return .hot
        case .critical: return .critical
        @unknown default: return .warm
        }
    }
}

public struct ThermalModule: NotchModule {
    public typealias State = ThermalLevel

    public static let descriptor = ModuleDescriptor(
        id: "system.thermal",
        name: "Thermal",
        summary: "How hot the Mac is running — a heat/throttle early warning.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<ThermalLevel>> {
        let clock = context.clock
        let interval = context.refreshSeconds(fallback: 5, minimum: 2)
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let level = ThermalLevel.from(ProcessInfo.processInfo.thermalState)
                    continuation.yield(Snapshot(value: level, freshness: .live, asOf: clock.now()))
                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: ThermalLevel, in slot: Slot) -> PillFace {
        Self.face(for: value)
    }

    public func detail(for value: ThermalLevel) -> [DetailRow] {
        let f = Self.face(for: value)
        return [DetailRow(id: "thermal", title: "Thermal", subtitle: Self.description(value),
                          tint: f.tint, symbolName: f.symbolName)]
    }

    /// Alert when the Mac newly gets hot, so you can back off before it stalls.
    public func notification(for value: ThermalLevel, previous: ThermalLevel?) -> ModuleAlert? {
        guard value == .critical || value == .hot,
              previous != .critical, previous != .hot, previous != nil else { return nil }
        // Fires once per rising edge (good→hot). Each episode gets a distinct id
        // so a second overheating later isn't silently deduped away.
        return ModuleAlert(id: "thermal-\(value)-\(Self.episodeToken())", title: "Mac is running hot",
                           body: "Thermal state: \(Self.label(value)). It may start throttling.")
    }

    /// A per-event token so repeat warnings aren't dropped by the notifier's
    /// permanent id-dedup. Seconds-resolution is unique enough — these
    /// transitions are minutes apart.
    static func episodeToken() -> Int { Int(Date().timeIntervalSince1970) }

    static func face(for level: ThermalLevel) -> PillFace {
        PillFace(text: label(level), symbolName: "thermometer",
                 tint: tint(level), tooltip: description(level))
    }
    static func label(_ level: ThermalLevel) -> String {
        switch level {
        case .cool: return "Cool"; case .warm: return "Warm"
        case .hot: return "Hot"; case .critical: return "Critical"
        }
    }
    static func tint(_ level: ThermalLevel) -> Tint {
        switch level {
        case .cool: return .good; case .warm: return .good
        case .hot: return .warning; case .critical: return .critical
        }
    }
    static func description(_ level: ThermalLevel) -> String {
        switch level {
        case .cool: return "Running cool"
        case .warm: return "A little warm — normal"
        case .hot: return "Hot — may start throttling"
        case .critical: return "Critical — throttling to cool down"
        }
    }
}
