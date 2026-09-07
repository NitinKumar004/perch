import Foundation
import IOKit.ps

/// A battery reading: charge percentage and its power state.
public struct BatterySample: Sendable, Equatable {
    public let percent: Int
    /// Actually gaining charge right now (from IOKit's `Is Charging`), NOT merely
    /// plugged in — so a full or held-at-80% battery on AC reads false, honestly.
    public let isCharging: Bool
    /// On external/AC power (may or may not be actively charging).
    public let isPluggedIn: Bool
    /// False on desktops / when no battery is present.
    public let hasBattery: Bool

    public init(percent: Int, isCharging: Bool, isPluggedIn: Bool = false, hasBattery: Bool) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
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
        // The real "actively charging" flag — NOT the AC-power state. Being on AC
        // (kIOPSACPowerValue) does not mean gaining charge (full, or held at 80%).
        let isCharging = (info[kIOPSIsChargingKey as String] as? Bool) ?? false
        let isPluggedIn = (info[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
        return BatterySample(percent: percent, isCharging: isCharging,
                             isPluggedIn: isPluggedIn, hasBattery: true)
    }
}
