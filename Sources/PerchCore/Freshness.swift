import Foundation

/// How much we trust a value *right now*.
///
/// Freshness is the heart of the "never a confident lie" promise: every value
/// the HUD shows carries one of these, so the UI can always be honest about
/// whether it is live, still resolving, or merely the last thing we saw.
public enum Freshness: Equatable, Sendable {
    /// Confirmed current by a successful fetch.
    case live
    /// The upstream is still computing the answer (e.g. GitHub mergeability).
    case computing
    /// The last known value, but a refresh is overdue or failed. Carries how
    /// long ago the value was confirmed so the UI can say "as of 2m ago".
    case stale(since: Date)
    /// No value has ever been confirmed.
    case unknown
    /// A refresh failed in a way the user may need to act on (e.g. auth).
    case error(String)

    /// Whether this value is safe to present as the current truth.
    public var isTrustworthy: Bool {
        if case .live = self { return true }
        return false
    }
}
