import Foundation
import PerchCore
import PerchModuleKit

/// A fully local countdown / focus timer. It counts down from a configurable
/// number of minutes (`minutes` setting, default 25 — a pomodoro) and shows the
/// remaining time; when it reaches zero it reads "done" until reset.
///
/// No network, no persistence — a simple, honest local module. It demonstrates
/// a module whose state advances on its own clock rather than from a fetch.
public struct TimerModule: NotchModule {
    public typealias State = Int   // seconds remaining

    public static let descriptor = ModuleDescriptor(
        id: "focus.timer",
        name: "Focus timer",
        summary: "A local countdown / pomodoro timer.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Int>> {
        let clock = context.clock
        let minutes = Int(context.settings["minutes"] ?? "") ?? 25
        let total = max(1, minutes) * 60

        return AsyncStream { continuation in
            let task = Task {
                let start = clock.now()
                while !Task.isCancelled {
                    let elapsed = Int(clock.now().timeIntervalSince(start))
                    let remaining = max(0, total - elapsed)
                    continuation.yield(Snapshot(value: remaining, freshness: .live, asOf: clock.now()))
                    if remaining == 0 { break }
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: Int, in slot: Slot) -> PillFace {
        if value == 0 {
            return PillFace(text: "done", symbolName: "checkmark.circle", tint: .good, tooltip: "Focus session complete")
        }
        return PillFace(text: Self.format(value), symbolName: "timer",
                        tint: .accent, tooltip: "Focus timer")
    }

    /// mm:ss.
    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
