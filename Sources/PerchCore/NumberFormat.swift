import Foundation

/// Human-readable compact counts, in one place — "1.2K", "3.5M", "2.4B". The
/// count analogue of `ByteFormat`: modules and the charts that render them (token
/// counts, message counts, tool calls) format through this instead of each
/// re-rolling a 1000-scaling loop, so the K/M/B convention can't drift between a
/// value and the chart beside it.
public enum NumberFormat {
    public static func compact(_ n: Int) -> String { compact(Double(n)) }

    /// A compact count like "3.5B" / "76.8M" / "12.3K" / "500". Scales by 1000
    /// through K/M/B/T, whole below the first tier (a raw count reads as "500")
    /// or once a scaled value is ≥ 100, else one decimal. Like `ByteFormat`, it
    /// rounds BEFORE choosing the tier, so a value just under a boundary rolls up
    /// ("1.0M", never the impossible "1000.0K").
    public static func compact(_ n: Double) -> String {
        let units = ["", "K", "M", "B", "T"]
        let divisor = 1000.0
        var v = Swift.max(0, n)
        var i = 0
        while v >= divisor && i < units.count - 1 { v /= divisor; i += 1 }

        func render(_ v: Double, _ i: Int) -> String {
            let decimals = (i == 0 || v >= 100) ? 0 : 1
            let factor = decimals == 0 ? 1.0 : 10.0
            let rounded = (v * factor).rounded() / factor
            // Rounding tipped it into the next tier → roll up (no "1000K").
            if rounded >= divisor && i < units.count - 1 { return render(rounded / divisor, i + 1) }
            // Rounding pushed a 1-decimal value to ≥ 100 → show it whole ("100M").
            if decimals == 1 && rounded >= 100 { return render(rounded, i) }
            return String(format: "%.\(decimals)f%@", rounded, units[i])
        }
        return render(v, i)
    }
}
