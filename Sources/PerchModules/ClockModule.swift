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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return PillFace(text: formatter.string(from: value), symbolName: nil, tint: .neutral, tooltip: "Local time")
    }
}
