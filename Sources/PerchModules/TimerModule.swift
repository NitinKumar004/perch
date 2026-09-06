import Foundation
import PerchCore
import PerchModuleKit

/// Timer state for one tick: remaining seconds + whether paused.
public struct TimerState: Sendable, Equatable {
    public var remaining: Int
    public var isPaused: Bool
    public var id: String   // which timer these controls target
}

/// A local countdown / pomodoro timer with pause & reset controls in the panel.
/// The countdown is driven by a shared `TimerController` so the panel buttons
/// can pause/resume/reset it — the timer is the one interactive local module.
public struct TimerModule: NotchModule {
    public typealias State = TimerState

    public static let descriptor = ModuleDescriptor(
        id: "focus.timer",
        name: "Focus timer",
        summary: "A local countdown / pomodoro timer with pause & reset.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let controller: TimerController

    public init(controller: TimerController) {
        self.controller = controller
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<TimerState>> {
        let clock = context.clock
        let controller = controller
        let minutes = Int(context.settings["minutes"] ?? "") ?? 25
        let total = max(1, minutes) * 60
        let id = "\(minutes)"

        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let now = clock.now()
                    let (elapsed, paused) = await controller.elapsed(id: id, now: now)
                    let remaining = max(0, total - Int(elapsed))
                    continuation.yield(Snapshot(
                        value: TimerState(remaining: remaining, isPaused: paused, id: id),
                        freshness: .live, asOf: now))
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: TimerState, in slot: Slot) -> PillFace {
        if value.remaining == 0 {
            return PillFace(text: "done", symbolName: "checkmark.circle", tint: .good, tooltip: "Focus session complete")
        }
        let symbol = value.isPaused ? "pause.circle" : "timer"
        return PillFace(text: Self.format(value.remaining), symbolName: symbol, tint: .accent,
                        tooltip: value.isPaused ? "Paused" : "Focus timer")
    }

    public func detail(for value: TimerState) -> [DetailRow] {
        [
            DetailRow(id: "timer.toggle", title: value.isPaused ? "Resume" : "Pause",
                      tint: .accent, symbolName: value.isPaused ? "play.fill" : "pause.fill",
                      action: "timer.toggle:\(value.id)"),
            DetailRow(id: "timer.reset", title: "Reset",
                      tint: .neutral, symbolName: "arrow.counterclockwise",
                      action: "timer.reset:\(value.id)"),
        ]
    }

    /// mm:ss.
    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
