import Foundation
import PerchCore
import PerchModuleKit

/// macOS's thermal-PRESSURE signal — how close the Mac is to throttling — NOT a
/// temperature. macOS exposes no public temperature on Apple Silicon; it exposes
/// `ProcessInfo.thermalState`, which weights die temp, sustained power and fan
/// headroom toward "am I about to slow down". So it can read "Nominal" while the
/// chassis is warm to the touch (there's still headroom before throttling). We
/// label it honestly as throttle pressure, never as a temperature we don't measure.
public enum ThermalLevel: Sendable, Equatable {
    // Case names are the internal throttle-pressure levels (nominal → critical).
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
        name: "Thermal pressure",
        summary: "How close the Mac is to throttling (macOS thermal pressure, not a temperature).",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<ThermalLevel>> {
        .periodic(every: context.refreshSeconds(fallback: 5, minimum: 2), clock: context.clock) {
            ThermalLevel.from(ProcessInfo.processInfo.thermalState)
        }
    }

    public func face(for value: ThermalLevel, in slot: Slot) -> PillFace {
        Self.face(for: value)
    }

    public func detail(for value: ThermalLevel) -> [DetailRow] {
        // The panel spells out the level word + plain-language state (the pill is
        // just the bar), and repeats the bar so the mapping is obvious.
        return [DetailRow(id: "thermal", title: Self.label(value),
                          subtitle: Self.description(value),
                          tint: Self.tint(value), symbolName: "gauge.medium",
                          progress: Self.fraction(value))]
    }

    /// Alert when throttle pressure newly rises to serious/critical, so you can
    /// back off before the Mac actually slows down.
    public func notification(for value: ThermalLevel, previous: ThermalLevel?) -> ModuleAlert? {
        guard value == .critical || value == .hot,
              previous != .critical, previous != .hot, previous != nil else { return nil }
        // Fires once per rising edge. Each episode gets a distinct id so a second
        // spike later isn't silently deduped away.
        return ModuleAlert(id: "thermal-\(value)-\(AlertEpisode.token())", title: "Mac is under thermal pressure",
                           body: "\(Self.label(value)) — the Mac may start throttling to cool down.")
    }

    static func face(for level: ThermalLevel) -> PillFace {
        // A gauge + a filled bar, not a jargon word: nearly-empty = fine, full =
        // throttling. Reads at a glance without knowing what "Nominal" means. The
        // word + explanation live in the tooltip and the panel row.
        PillFace(text: "", symbolName: "gauge.medium", tint: tint(level),
                 tooltip: tooltip(level), progress: fraction(level))
    }
    /// The bar fill for each pressure level — more fill = more thermal pressure.
    static func fraction(_ level: ThermalLevel) -> Double {
        // .cool is the everyday baseline — keep it near-empty so a glance reads
        // "fine" (a quarter-full bar looked like mild pressure all the time).
        switch level {
        case .cool: return 0.12; case .warm: return 0.45
        case .hot: return 0.75; case .critical: return 1.0
        }
    }
    /// The pill word — macOS's own throttle-pressure vocabulary, never a
    /// temperature word like "Cool/Hot" (which we can't actually measure).
    static func label(_ level: ThermalLevel) -> String {
        switch level {
        case .cool: return "Nominal"; case .warm: return "Fair"
        case .hot: return "Serious"; case .critical: return "Critical"
        }
    }
    static func tint(_ level: ThermalLevel) -> Tint {
        switch level {
        case .cool: return .good; case .warm: return .good
        case .hot: return .warning; case .critical: return .critical
        }
    }
    /// Panel subtitle — plain-language throttle state.
    static func description(_ level: ThermalLevel) -> String {
        switch level {
        case .cool: return "No throttling — plenty of headroom"
        case .warm: return "Slight pressure — still fine"
        case .hot: return "Under pressure — may start throttling"
        case .critical: return "Throttling now to cool down"
        }
    }
    /// Pill tooltip — the honest disclaimer that this is not a temperature.
    static func tooltip(_ level: ThermalLevel) -> String {
        "\(description(level)) · macOS throttle-pressure signal, not a temperature — it can read Nominal while the Mac feels warm."
    }
}
