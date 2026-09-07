import Foundation

/// Human-readable byte sizes and rates, in one place. Modules that show storage,
/// memory or throughput all format through this rather than each rolling their
/// own 1024-scaling loop.
public enum ByteFormat {
    /// Scale a byte count down through the given units until it's < 1024.
    private static func scaled(_ value: Double, units: [String]) -> (value: Double, index: Int, unit: String) {
        var v = Swift.max(0, value)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return (v, i, units[i])
    }

    /// A size like "48.1 GB", scaled by 1024 — the right convention for MEMORY
    /// quantities (RAM, swap), which are inherently binary. Whole number for
    /// bytes/KB and for large values, one decimal in between.
    public static func size(_ bytes: UInt64) -> String {
        let (v, i, unit) = scaled(Double(bytes), units: ["B", "KB", "MB", "GB", "TB"])
        let text = (v >= 100 || i <= 1) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return "\(text) \(unit)"
    }

    /// A STORAGE size like "512 GB", scaled by 1000 — the decimal convention
    /// Finder / Disk Utility / About This Mac use for disks, so Perch's free-space
    /// number matches what the user sees there (1024-scaling would read ~7% low).
    public static func storage(_ bytes: UInt64) -> String {
        var v = Swift.max(0, Double(bytes))
        let units = ["B", "KB", "MB", "GB", "TB"]
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        let text = (v >= 100 || i <= 1) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return "\(text) \(units[i])"
    }

    /// A throughput like "1.2 MB/s". Whole number only for bytes/s and large
    /// values, one decimal otherwise (so KB/s and MB/s read precisely).
    public static func rate(_ bytesPerSecond: Double) -> String {
        let (v, i, unit) = scaled(bytesPerSecond, units: ["B", "KB", "MB", "GB"])
        let text = (v >= 100 || i == 0) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return "\(text) \(unit)/s"
    }
}
