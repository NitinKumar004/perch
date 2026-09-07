import Foundation
import PerchCore

public extension AsyncStream {
    /// A periodic sampling stream — the shape almost every "read a fresh value
    /// every N seconds" module needs. It optionally emits a `seed` immediately
    /// (so a panel row appears before the first real sample), then calls
    /// `sample` every `interval` seconds, wrapping each non-nil result as a
    /// `.live` snapshot stamped with the injected clock. A tick where `sample`
    /// returns nil is skipped (a transient read failure keeps the last value).
    ///
    /// This centralises the Task lifecycle, the cancellation check and the
    /// `onTermination` teardown that every sampling module used to hand-roll, so
    /// there is one correct implementation instead of a dozen copies.
    ///
    /// Stateful samplers (a rolling history), delta samplers (throughput) and
    /// hysteresis/event-driven modules keep their own `stream` — this is for the
    /// genuinely-common stateless case, not a one-size-fits-all.
    static func periodic<Value: Sendable>(
        every interval: Double,
        clock: any Clock,
        seed: Value? = nil,
        sample: @escaping @Sendable () async -> Value?
    ) -> AsyncStream<Snapshot<Value>> where Element == Snapshot<Value> {
        AsyncStream { continuation in
            let task = Task {
                if let seed {
                    // The seed is a placeholder shown before the first real
                    // sample, so it's `.unknown` — never mistaken for live data.
                    continuation.yield(Snapshot(value: seed, freshness: .unknown, asOf: clock.now()))
                }
                while !Task.isCancelled {
                    if let value = await sample() {
                        continuation.yield(Snapshot(value: value, freshness: .live, asOf: clock.now()))
                    }
                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
