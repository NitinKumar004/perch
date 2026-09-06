import Foundation
import PerchCore
import PerchModuleKit

/// The formatted time the module emits. The formatting choices (12/24-hour,
/// seconds) are applied in `stream` — where settings live — so `face` stays a
/// pure, allocation-free string passthrough called every tick.
public struct ClockFace: Sendable, Equatable {
    public let text: String
    public init(text: String) { self.text = text }
}

/// A fully local, zero-setup module: the current time. Configurable via
/// `format` (24 | 12) and a `showSeconds` toggle — the user sees exactly the
/// clock they want. Needs no connection and starts producing immediately.
public struct ClockModule: NotchModule {
    public typealias State = ClockFace

    public static let descriptor = ModuleDescriptor(
        id: "system.clock",
        name: "Clock",
        summary: "The current time, in the format you choose.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<ClockFace>> {
        let clock = context.clock
        let twelveHour = context.settings["format"] == "12"
        let showSeconds = context.bool("showSeconds", fallback: false)
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let now = clock.now()
                    let face = Self.render(now, twelveHour: twelveHour, showSeconds: showSeconds)
                    continuation.yield(Snapshot(value: face, freshness: .live, asOf: now))
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: ClockFace, in slot: Slot) -> PillFace {
        PillFace(text: value.text, symbolName: nil, tint: .neutral, tooltip: "Local time")
    }

    /// Built from calendar components rather than a DateFormatter — this runs
    /// every second, so it avoids allocating a formatter each time (and sidesteps
    /// DateFormatter's non-Sendable global caching).
    static func render(_ date: Date, twelveHour: Bool, showSeconds: Bool) -> ClockFace {
        var units: Set<Calendar.Component> = [.hour, .minute]
        if showSeconds { units.insert(.second) }
        let c = Calendar.current.dateComponents(units, from: date)
        let hour24 = c.hour ?? 0
        let hour = twelveHour ? (hour24 % 12 == 0 ? 12 : hour24 % 12) : hour24
        let hourText = twelveHour ? "\(hour)" : String(format: "%02d", hour)
        var text = "\(hourText):" + String(format: "%02d", c.minute ?? 0)
        if showSeconds { text += ":" + String(format: "%02d", c.second ?? 0) }
        if twelveHour { text += hour24 < 12 ? " AM" : " PM" }
        return ClockFace(text: text)
    }
}
