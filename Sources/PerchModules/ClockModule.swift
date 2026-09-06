import Foundation
import PerchCore
import PerchModuleKit

/// A fully local, zero-setup module: the current time. It needs no connection
/// and starts producing immediately — the simplest possible proof that the
/// module → snapshot → pill path works end to end.
public struct ClockModule: NotchModule {
    public typealias State = Date

    public static let descriptor = ModuleDescriptor(
        id: "system.clock",
        name: "Clock",
        summary: "The current time, updated every second.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Date>> {
        let clock = context.clock
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let now = clock.now()
                    continuation.yield(Snapshot(value: now, freshness: .live, asOf: now))
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: Date, in slot: Slot) -> PillFace {
        // Built from calendar components rather than a DateFormatter — `face` is
        // called every second, and this avoids allocating a formatter each time
        // (and sidesteps DateFormatter's non-Sendable global caching).
        let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
        let text = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return PillFace(text: text, symbolName: nil, tint: .neutral, tooltip: "Local time")
    }
}
