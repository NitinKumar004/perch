import Foundation

/// A shared, process-wide record of the latest GitHub rate-limit reading, so
/// every poller can back off together when the budget runs low. GitHub's REST
/// limit is per-token, not per-endpoint, so one shared gate is the correct
/// model — a multi-repo sweep and the update check draw from the same pool.
public actor RateLimitGate {
    private var latest: RateLimit?

    public init() {}

    /// Record the most recent reading (ignores nil so a 304 doesn't clear it).
    public func record(_ limit: RateLimit?) {
        guard let limit else { return }
        latest = limit
    }

    /// The recommended delay before the next call, or 0 if we're comfortably
    /// under the limit or have no reading yet.
    public func throttleDelay(now: Date = Date()) -> TimeInterval {
        latest?.throttleDelay(now: now) ?? 0
    }

    /// The last-seen remaining budget, for display/tests.
    public func remaining() -> Int? { latest?.remaining }
}
