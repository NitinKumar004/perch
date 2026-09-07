import Foundation

/// The semantic colour language of the HUD.
///
/// Modules speak in *meaning* (`.good`, `.critical`), never in raw colours, so
/// the shell can keep one consistent palette and the same state always reads
/// the same way. `.accent` is the brand colour and is deliberately **not** a
/// status — it never means "attention".
public enum Tint: String, Codable, Sendable {
    case neutral
    case good
    case warning
    case critical
    case info
    case accent
}

public extension Tint {
    /// The status tint for a 0–100 usage percentage: `.good` below `warn`,
    /// `.warning` from `warn`, `.critical` from `critical`. One home for the
    /// "green/amber/red by percent" rule every vitals-style module shares — pass
    /// the thresholds that fit the metric (disk fills later than CPU).
    static func forUsage(percent: Int, warn: Int, critical: Int = 90) -> Tint {
        if percent >= critical { return .critical }
        if percent >= warn { return .warning }
        return .good
    }
}
