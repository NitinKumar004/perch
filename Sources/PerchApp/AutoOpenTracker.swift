import Foundation

/// Decides when a module going red should auto-open the detail panel, tracking
/// just enough state to be correct — extracted so the exact rule is unit-testable
/// without driving the async bind loop.
///
/// The rules, learned the hard way:
/// - **Only live observations count.** A module emits a `.unknown` placeholder
///   seed before its first real poll. If that seed set the baseline, the first
///   *real* value of an already-failing build would look like a fresh good→red
///   transition and pop the panel on every launch/reload. Non-live renders
///   (seed, stale, error) are ignored entirely.
/// - **The first live render is a silent baseline** — an already-red module at
///   startup never opens the panel (the red menu-bar bird shows it instead).
/// - **Only a genuine non-red → red transition** across live renders opens it.
///   (Red → green → red *does* open again — a second real failure is news.)
/// - **`opensOnCritical == false`** (a to-do like PRs, not a live incident)
///   never opens the panel.
struct AutoOpenTracker {
    let opensOnCritical: Bool
    /// nil until the first live render; then the last live critical state.
    private var wasCritical: Bool?

    init(opensOnCritical: Bool) {
        self.opensOnCritical = opensOnCritical
    }

    /// Feed one render's state. Returns true iff the panel should auto-open now.
    mutating func observe(isCritical: Bool, isLive: Bool) -> Bool {
        guard isLive else { return false }   // ignore placeholder/stale/error
        let open = isCritical && wasCritical == false && opensOnCritical
        wasCritical = isCritical
        return open
    }
}
