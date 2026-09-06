import Foundation

/// Computes an exponential backoff delay for repeated failures, so a persistent
/// error (revoked token, rate limit, unreachable host) doesn't turn into a tight
/// retry loop that hammers the server and worsens rate-limit lockouts.
public struct Backoff: Sendable {
    public let base: TimeInterval
    public let cap: TimeInterval

    public init(base: TimeInterval = 10, cap: TimeInterval = 300) {
        self.base = base
        self.cap = cap
    }

    /// Delay after `consecutiveFailures` failures (1 = first failure). Doubles
    /// each time up to `cap`.
    public func delay(consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        let doubled = base * pow(2, Double(consecutiveFailures - 1))
        return min(cap, doubled)
    }
}
