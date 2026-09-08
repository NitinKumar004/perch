import Foundation

/// User-tunable warn/critical levels for the system metrics. One place decides
/// what counts as yellow vs red, so a user can set the levels that fit their Mac
/// (a 64 GB machine treats 6 GB of swap very differently from a 8 GB one) instead
/// of living with hardcoded thresholds. Injected into the modules that colour by
/// level, so the same levels apply whether a metric is shown on its own or inside
/// a Combined pill. Thermal is deliberately absent — it's the OS's own
/// throttle-pressure signal, not a number we set.
public struct MetricThresholds: Sendable, Equatable, Codable {
    public var cpuWarn: Int
    public var cpuCritical: Int
    public var memoryWarn: Int
    public var memoryCritical: Int
    public var diskWarn: Int          // % used
    public var diskCritical: Int
    public var swapWarnGB: Double
    public var swapCriticalGB: Double
    public var loadWarnRatio: Double   // 1-min load average ÷ core count
    public var loadCriticalRatio: Double

    public init(cpuWarn: Int = 70, cpuCritical: Int = 90,
                memoryWarn: Int = 75, memoryCritical: Int = 90,
                diskWarn: Int = 85, diskCritical: Int = 95,
                swapWarnGB: Double = 2, swapCriticalGB: Double = 6,
                loadWarnRatio: Double = 0.9, loadCriticalRatio: Double = 1.5) {
        self.cpuWarn = cpuWarn
        self.cpuCritical = cpuCritical
        self.memoryWarn = memoryWarn
        self.memoryCritical = memoryCritical
        self.diskWarn = diskWarn
        self.diskCritical = diskCritical
        self.swapWarnGB = swapWarnGB
        self.swapCriticalGB = swapCriticalGB
        self.loadWarnRatio = loadWarnRatio
        self.loadCriticalRatio = loadCriticalRatio
    }

    /// Sensible out-of-the-box levels.
    public static let standard = MetricThresholds()

    /// Tolerant of older/partial config: any missing field falls back to the
    /// standard default rather than failing the whole decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MetricThresholds.standard
        cpuWarn = try c.decodeIfPresent(Int.self, forKey: .cpuWarn) ?? d.cpuWarn
        cpuCritical = try c.decodeIfPresent(Int.self, forKey: .cpuCritical) ?? d.cpuCritical
        memoryWarn = try c.decodeIfPresent(Int.self, forKey: .memoryWarn) ?? d.memoryWarn
        memoryCritical = try c.decodeIfPresent(Int.self, forKey: .memoryCritical) ?? d.memoryCritical
        diskWarn = try c.decodeIfPresent(Int.self, forKey: .diskWarn) ?? d.diskWarn
        diskCritical = try c.decodeIfPresent(Int.self, forKey: .diskCritical) ?? d.diskCritical
        swapWarnGB = try c.decodeIfPresent(Double.self, forKey: .swapWarnGB) ?? d.swapWarnGB
        swapCriticalGB = try c.decodeIfPresent(Double.self, forKey: .swapCriticalGB) ?? d.swapCriticalGB
        loadWarnRatio = try c.decodeIfPresent(Double.self, forKey: .loadWarnRatio) ?? d.loadWarnRatio
        loadCriticalRatio = try c.decodeIfPresent(Double.self, forKey: .loadCriticalRatio) ?? d.loadCriticalRatio
    }

    // MARK: - Level → tint (the one place a value becomes a status colour)

    public func cpuTint(_ percent: Int) -> Tint {
        Tint.forUsage(percent: percent, warn: cpuWarn, critical: cpuCritical)
    }
    public func memoryTint(_ percent: Int) -> Tint {
        Tint.forUsage(percent: percent, warn: memoryWarn, critical: memoryCritical)
    }
    public func diskTint(_ usedPercent: Int) -> Tint {
        Tint.forUsage(percent: usedPercent, warn: diskWarn, critical: diskCritical)
    }
    public func swapTint(bytes: UInt64) -> Tint {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= swapCriticalGB { return .critical }
        if gb >= swapWarnGB { return .warning }
        return .good
    }
    public func loadTint(ratio: Double) -> Tint {
        if ratio >= loadCriticalRatio { return .critical }
        if ratio >= loadWarnRatio { return .warning }
        return .good
    }

    /// Swap thresholds in bytes, for the "crossed into heavy" alert edge.
    public var swapCriticalBytes: UInt64 { UInt64(swapCriticalGB * 1_073_741_824) }
}
