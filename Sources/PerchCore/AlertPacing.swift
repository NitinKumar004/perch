import Foundation

/// How eagerly a red metric is allowed to pop the panel / banner — the user-
/// tunable damping that stops a value flapping at its threshold from alerting
/// every few seconds. Two knobs; hysteresis (recover-to-green before re-alerting)
/// is automatic and rides on the warn↔critical gap in `MetricThresholds`.
public struct AlertPacing: Sendable, Equatable, Codable {
    /// Seconds a metric must stay red *continuously* before it counts as an
    /// incident — so a momentary spike or a flap never fires. 0 = fire instantly.
    public var dwellSeconds: Int
    /// Minimum seconds between alerts for the *same* metric, even across genuine
    /// recover-then-fail cycles. 0 = no cooldown.
    public var cooldownSeconds: Int

    public init(dwellSeconds: Int = 10, cooldownSeconds: Int = 120) {
        self.dwellSeconds = dwellSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    /// Sensible defaults: a 10s dwell and a 2-minute cooldown.
    public static let standard = AlertPacing()

    /// Tolerant of older/partial config: missing fields fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertPacing.standard
        dwellSeconds = try c.decodeIfPresent(Int.self, forKey: .dwellSeconds) ?? d.dwellSeconds
        cooldownSeconds = try c.decodeIfPresent(Int.self, forKey: .cooldownSeconds) ?? d.cooldownSeconds
    }
}
