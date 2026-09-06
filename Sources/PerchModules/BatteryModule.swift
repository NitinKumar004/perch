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
        let clock = context.clock
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(Snapshot(value: BatteryReader.read(), freshness: .live, asOf: clock.now()))
                    try? await Task.sleep(for: .seconds(20))   // battery moves slowly
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: BatterySample, in slot: Slot) -> PillFace {
        guard value.hasBattery else {
            return PillFace(text: "AC", symbolName: "powerplug", tint: .neutral, tooltip: "No battery (on AC)")
        }
        let tint: Tint = value.isCharging ? .good
            : (value.percent <= 10 ? .critical : (value.percent <= 20 ? .warning : .good))
        let symbol = value.isCharging ? "battery.100.bolt" : batterySymbol(value.percent)
        return PillFace(text: "\(value.percent)%", symbolName: symbol, tint: tint,
                        tooltip: value.isCharging ? "Charging · \(value.percent)%" : "Battery \(value.percent)%")
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
