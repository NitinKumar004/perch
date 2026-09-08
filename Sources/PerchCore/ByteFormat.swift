import Foundation

/// Human-readable byte sizes and rates, in one place. Modules that show storage,
/// memory or throughput all format through this rather than each rolling their
/// own 1024-scaling loop.
public enum ByteFormat {
    /// The one scaling+formatting routine every size/rate goes through — no more
    /// re-rolled loops. Scales `value` down by `divisor` through `units`, then
    /// renders with whole numbers when the index is at/below `wholeBelow` (small
    /// units read cleaner without decimals) or the value is ≥ 100, else one
    /// decimal. Crucially it rounds BEFORE deciding the unit, so a value just
    /// under a boundary (1023.6 GB) rolls up to the next unit ("1.0 TB") instead
    /// of rendering the impossible "1024 GB".
    private static func format(_ value: Double, divisor: Double, units: [String],
                              wholeBelow: Int, suffix: String) -> String {
        var v = Swift.max(0, value)
        var i = 0
        while v >= divisor && i < units.count - 1 { v /= divisor; i += 1 }

        func render(_ v: Double, _ i: Int) -> String {
            let decimals = (v >= 100 || i <= wholeBelow) ? 0 : 1
            let factor = decimals == 0 ? 1.0 : 10.0
            let rounded = (v * factor).rounded() / factor
            // Rounding tipped it to the next unit → roll up (no "1024 GB").
            if rounded >= divisor && i < units.count - 1 { return render(rounded / divisor, i + 1) }
            // Rounding pushed a 1-decimal value to ≥100 → show it whole ("100 MB").
            if decimals == 1 && rounded >= 100 { return render(rounded, i) }
            return String(format: "%.\(decimals)f %@\(suffix)", rounded, units[i])
        }
        return render(v, i)
    }

    /// A size like "48.1 GB", scaled by 1024 — the right convention for MEMORY
    /// quantities (RAM, swap), which are inherently binary. Whole number for
    /// bytes/KB and for large values, one decimal in between.
    public static func size(_ bytes: UInt64) -> String {
        format(Double(bytes), divisor: 1024, units: ["B", "KB", "MB", "GB", "TB"], wholeBelow: 1, suffix: "")
    }

    /// A STORAGE size like "512 GB", scaled by 1000 — the decimal convention
    /// Finder / Disk Utility / About This Mac use for disks, so Perch's free-space
    /// number matches what the user sees there (1024-scaling would read ~7% low).
    public static func storage(_ bytes: UInt64) -> String {
        format(Double(bytes), divisor: 1000, units: ["B", "KB", "MB", "GB", "TB"], wholeBelow: 1, suffix: "")
    }

    /// A throughput like "1.2 MB/s". Whole number only for bytes/s and large
    /// values, one decimal otherwise (so KB/s and MB/s read precisely).
    public static func rate(_ bytesPerSecond: Double) -> String {
        format(bytesPerSecond, divisor: 1024, units: ["B", "KB", "MB", "GB"], wholeBelow: 0, suffix: "/s")
    }
}
