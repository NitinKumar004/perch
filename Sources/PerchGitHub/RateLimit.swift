import Foundation

/// A snapshot of GitHub's REST rate-limit headers. GitHub returns
/// `X-RateLimit-Remaining` (calls left in the window) and `X-RateLimit-Reset`
/// (Unix epoch when the window refills) on every authenticated response.
public struct RateLimit: Sendable, Equatable {
    public let remaining: Int
    public let reset: Date

    public init(remaining: Int, reset: Date) {
        self.remaining = remaining
        self.reset = reset
    }

    /// Parse the headers off a response, or nil if they're absent (e.g. a 304 or
    /// a GraphQL error). Case-insensitive lookup via `HTTPResponse.header`.
    public static func from(_ response: HTTPResponse) -> RateLimit? {
        guard let remainingRaw = response.header("X-RateLimit-Remaining"),
              let remaining = Int(remainingRaw),
              let resetRaw = response.header("X-RateLimit-Reset"),
              let resetEpoch = Double(resetRaw) else { return nil }
        return RateLimit(remaining: remaining, reset: Date(timeIntervalSince1970: resetEpoch))
    }

    /// How long to wait before the next call, given how close we are to the
    /// limit. Above `floor` calls remaining → no wait. At or below it → wait
    /// until the window resets (clamped to ≥0), so a big fan-out backs off
    /// instead of getting 403-rate-limited mid-sweep.
    public func throttleDelay(now: Date, floor: Int = 10) -> TimeInterval {
        guard remaining <= floor else { return 0 }
        return max(0, reset.timeIntervalSince(now))
    }
}
