import Foundation

/// Shared, mutable state for focus timers so the panel can pause/reset them —
/// the one place interactive control lives, since modules are otherwise pure.
/// Keyed by a timer id (its configured length), so independent timers don't
/// interfere. An `actor`: the module reads it each tick, the UI mutates it.
public actor TimerController {
    private struct State {
        var startedAt: Date
        var isPaused: Bool
        /// Seconds already elapsed before the current (un)pause segment.
        var accumulated: TimeInterval
    }
    private var states: [String: State] = [:]

    public init() {}

    private func state(for id: String, now: Date) -> State {
        if let s = states[id] { return s }
        let fresh = State(startedAt: now, isPaused: false, accumulated: 0)
        states[id] = fresh
        return fresh
    }

    /// Seconds elapsed for `id`, and whether it's paused.
    public func elapsed(id: String, now: Date) -> (elapsed: TimeInterval, isPaused: Bool) {
        let s = state(for: id, now: now)
        let running = s.isPaused ? 0 : now.timeIntervalSince(s.startedAt)
        return (s.accumulated + running, s.isPaused)
    }

    /// Pause ⇄ resume, banking elapsed time so the count is continuous.
    public func togglePause(id: String, now: Date) {
        var s = state(for: id, now: now)
        if s.isPaused {
            s.isPaused = false
            s.startedAt = now
        } else {
            s.accumulated += now.timeIntervalSince(s.startedAt)
            s.isPaused = true
        }
        states[id] = s
    }

    /// Restart from zero, running.
    public func reset(id: String, now: Date) {
        states[id] = State(startedAt: now, isPaused: false, accumulated: 0)
    }
}
