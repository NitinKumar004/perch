import Foundation
import PerchCore

/// Decides when a module going red should auto-open the detail panel (and fire
/// its reason banner), tracking just enough state to be correct AND to damp a
/// value that flaps at its threshold — extracted so the exact rule is unit-
/// testable without driving the async bind loop.
///
/// The rules, learned the hard way:
/// - **Only live observations count.** A module emits a `.unknown` placeholder
///   seed before its first real poll; a non-live render (seed, stale, error) is
///   ignored entirely, so a placeholder never looks like a transition.
/// - **The first live render is a silent baseline.** An already-red module at
///   startup never opens the panel (the red menu-bar bird shows it instead).
/// - **Dwell.** A metric must stay red *continuously* for `dwell` before it
///   counts, so a momentary spike or a flap never fires.
/// - **Hysteresis.** Once it has fired for a red spell it won't fire again until
///   the metric fully recovers to green — a dip to amber (warning) is not a
///   recovery. So a value bouncing red↔amber at its limit alerts once, not every
///   tick. The recovery band is the warn↔critical gap the user already sets.
/// - **Cooldown.** Even across a genuine green→red→red new incident, a metric
///   won't alert again until `cooldown` has elapsed since its last alert.
/// - **`opensOnCritical == false`** (a to-do like PRs, not a live incident)
///   never opens the panel.
///
/// One tracker runs per bound stream and sees that stream's pill tint. A Combined
/// pill reports the worst-of its members, so a Combined tracker treats the whole
/// pill as one incident: it re-arms only when the *pill* fully recovers to green,
/// and a second member going red while a first is still red is not a new alert.
struct AutoOpenTracker {
    let opensOnCritical: Bool
    let dwell: TimeInterval
    let cooldown: TimeInterval

    private var seenLive = false
    /// Start of the current *continuous* red spell; nil whenever the last live
    /// sample wasn't red.
    private var redSince: Date?
    /// True once we've fired for the current red spell (or adopted an already-red
    /// baseline); cleared only when the metric recovers to green. This is the
    /// hysteresis latch that stops red↔amber flapping from re-firing.
    private var acknowledged = false
    private var lastAlertAt: Date?

    init(opensOnCritical: Bool, dwell: TimeInterval = 0, cooldown: TimeInterval = 0) {
        self.opensOnCritical = opensOnCritical
        self.dwell = dwell
        self.cooldown = cooldown
    }

    /// Feed one render's tint + freshness (and its clock time). Returns true iff
    /// the panel should auto-open now.
    mutating func observe(tint: Tint, isLive: Bool, now: Date) -> Bool {
        guard isLive, opensOnCritical else { return false }
        let firstLive = !seenLive
        seenLive = true

        switch tint {
        case .good:
            // Full recovery ends the incident — a later red spell may alert again.
            acknowledged = false
            redSince = nil
            return false

        case .critical:
            if redSince == nil { redSince = now }
            // Already red at first sight → adopt as an acknowledged baseline so an
            // at-launch failure never pops the panel.
            if firstLive { acknowledged = true; return false }
            // Dwell: must have been red continuously long enough.
            guard let since = redSince, now.timeIntervalSince(since) >= dwell else { return false }
            // Hysteresis: one alert per red spell until it recovers to green.
            guard !acknowledged else { return false }
            // Cooldown: not too soon after the last alert for this metric.
            if let last = lastAlertAt, now.timeIntervalSince(last) < cooldown {
                acknowledged = true   // suppressed, but latch so we don't recheck each tick
                return false
            }
            acknowledged = true
            lastAlertAt = now
            return true

        default:
            // Amber/other: not red now (breaks the continuous-red dwell window),
            // but NOT a recovery either — keep the `acknowledged` latch so a
            // dip-and-repop to red doesn't re-fire.
            redSince = nil
            return false
        }
    }

    /// Whether a module's OWN red alert (e.g. memory's sustained-high alert) may
    /// be delivered now, or falls inside the cooldown — and records it if allowed.
    /// This shares ONE cooldown clock with the auto-open above, so a red metric's
    /// banner/notification can't out-nag the user's configured pace through a
    /// module's own `notification()` channel. Callers pass this only for red
    /// (critical) alerts on an auto-open-eligible metric; amber and event alerts
    /// (thermal "serious", GitHub) are delivered normally.
    mutating func admitRedAlert(now: Date) -> Bool {
        if let last = lastAlertAt, now.timeIntervalSince(last) < cooldown { return false }
        lastAlertAt = now
        return true
    }
}
