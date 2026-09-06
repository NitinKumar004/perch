import Foundation
import IOKit.ps

/// A battery reading: charge percentage and whether it's on AC/charging.
public struct BatterySample: Sendable, Equatable {
    public let percent: Int
    public let isCharging: Bool
    /// False on desktops / when no battery is present.
    public let hasBattery: Bool

    public init(percent: Int, isCharging: Bool, hasBattery: Bool) {
        self.percent = percent
        self.isCharging = isCharging
        self.hasBattery = hasBattery
    }
}

/// Reads battery charge + charging state from IOKit power sources.
enum BatteryReader {
    static func read() -> BatterySample {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let info = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return BatterySample(percent: 0, isCharging: false, hasBattery: false)
        }

        let current = info[kIOPSCurrentCapacityKey as String] as? Int ?? 0
        let max = info[kIOPSMaxCapacityKey as String] as? Int ?? 100
        let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0
        let state = info[kIOPSPowerSourceStateKey as String] as? String
        let isCharging = (state == (kIOPSACPowerValue as String))
        return BatterySample(percent: percent, isCharging: isCharging, hasBattery: true)
    }
}
