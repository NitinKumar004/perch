import Foundation
import PerchCore
import PerchModuleKit

/// A fully local, zero-setup module: battery charge. Green normally, amber when
/// low, red when critical; a bolt when charging. On a desktop (no battery) it
/// reports honestly rather than showing a fake 0%.
public struct BatteryModule: NotchModule {
    public typealias State = BatterySample

    public static let descriptor = ModuleDescriptor(
        id: "system.battery",
        name: "Battery",
        summary: "Battery charge and charging state, sampled locally.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<BatterySample>> {
        // Battery moves slowly, so poll gently.
        .periodic(every: 20, clock: context.clock) { BatteryReader.read() }
    }

    public func face(for value: BatterySample, in slot: Slot) -> PillFace {
        guard value.hasBattery else {
            return PillFace(text: "AC", symbolName: "powerplug", tint: .neutral, tooltip: "No battery (on AC)")
        }
        let tint: Tint = (value.isCharging || value.isPluggedIn) ? .good
            : (value.percent <= 10 ? .critical : (value.percent <= 20 ? .warning : .good))
        // Bolt only when actually gaining charge; a plug when on AC but not
        // charging (full / held at 80%); a battery glyph on battery power.
        let symbol: String
        let tooltip: String
        if value.isCharging {
            symbol = "battery.100.bolt"; tooltip = "Charging · \(value.percent)%"
        } else if value.isPluggedIn {
            symbol = "powerplug"; tooltip = "Plugged in, not charging · \(value.percent)%"
        } else {
            symbol = batterySymbol(value.percent); tooltip = "On battery · \(value.percent)%"
        }
        return PillFace(text: "\(value.percent)%", symbolName: symbol, tint: tint, tooltip: tooltip)
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<15:  return "battery.0"
        case ..<40:  return "battery.25"
        case ..<65:  return "battery.50"
        case ..<90:  return "battery.75"
        default:     return "battery.100"
        }
    }
}
