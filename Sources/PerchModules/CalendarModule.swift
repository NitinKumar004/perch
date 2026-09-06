import Foundation
import PerchCore
import PerchModuleKit
#if canImport(EventKit)
import EventKit
#endif

/// The next event on your calendar, or a "clear" marker.
public struct NextEvent: Sendable, Equatable {
    public var title: String
    public var startsAt: Date
    public var isAllDay: Bool
    /// nil = nothing upcoming; used to render a calm "clear" pill.
    public static let none = NextEvent(title: "", startsAt: .distantFuture, isAllDay: false)
    public var hasEvent: Bool { self != NextEvent.none }
    public init(title: String, startsAt: Date, isAllDay: Bool) {
        self.title = title
        self.startsAt = startsAt
        self.isAllDay = isAllDay
    }
}

/// Shows your next calendar event and a live countdown, so a meeting never
/// sneaks up on you. Reads the local Calendar database via EventKit (permission
/// requested on first run); nothing leaves the Mac.
public struct CalendarModule: NotchModule {
    public typealias State = NextEvent

    public static let descriptor = ModuleDescriptor(
        id: "system.calendar",
        name: "Next meeting",
        summary: "Your next calendar event, with a live countdown.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let reader: CalendarReading

    public init() { self.reader = SystemCalendarReader() }

    /// Test seam: inject a fake reader.
    init(reader: CalendarReading) { self.reader = reader }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<NextEvent>> {
        let clock = context.clock
        let reader = reader
        let lookaheadHours = Double(context.int("lookaheadHours", fallback: 12, minimum: 1, maximum: 48))
        let interval = context.refreshSeconds(fallback: 30, minimum: 15)

        return AsyncStream { continuation in
            let task = Task {
                var granted = false
                while !Task.isCancelled {
                    // Keep re-checking access so a denied→granted change (the user
                    // flips it in System Settings) recovers on its own, instead of
                    // ending the stream and staying blank until a restart.
                    if !granted { granted = await reader.requestAccess() }
                    if !granted {
                        continuation.yield(Snapshot(value: .none, freshness: .error("no calendar access"), asOf: clock.now()))
                        try? await Task.sleep(for: .seconds(60))   // slow retry
                        continue
                    }
                    let now = clock.now()
                    let next = await reader.nextEvent(from: now, within: lookaheadHours * 3600) ?? .none
                    continuation.yield(Snapshot(value: next, freshness: .live, asOf: now))
                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: NextEvent, in slot: Slot) -> PillFace {
        guard value.hasEvent else {
            return PillFace(text: "clear", symbolName: "calendar", tint: .neutral, tooltip: "No upcoming events")
        }
        let mins = Int(value.startsAt.timeIntervalSinceNow / 60)
        // Amber inside 5 minutes so an imminent meeting stands out.
        let tint: Tint = mins <= 5 ? .warning : .info
        return PillFace(text: Self.countdown(to: value.startsAt, now: Date()),
                        symbolName: "calendar", tint: tint,
                        tooltip: "\(value.title) — \(Self.countdown(to: value.startsAt, now: Date()))")
    }

    public func detail(for value: NextEvent) -> [DetailRow] {
        guard value.hasEvent else {
            return [DetailRow(id: "cal-clear", title: "Nothing upcoming", tint: .neutral, symbolName: "calendar")]
        }
        return [DetailRow(id: "cal-next", title: value.title,
                          subtitle: Self.countdown(to: value.startsAt, now: Date()) + " · " + Self.clockText(value.startsAt),
                          tint: .info, symbolName: "calendar.badge.clock")]
    }

    /// A compact countdown: "in 2h 5m", "in 8m", "now", or "started 3m ago".
    static func countdown(to date: Date, now: Date) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= -60 { return "started \(-secs / 60)m ago" }
        if secs <= 30 { return "now" }
        let mins = (secs + 59) / 60
        if mins < 60 { return "in \(mins)m" }
        return "in \(mins / 60)h \(mins % 60)m"
    }

    /// Local HH:MM, built from calendar components (no DateFormatter churn).
    static func clockText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// The calendar-read seam, so the module is testable without a real EKEventStore.
protocol CalendarReading: Sendable {
    func requestAccess() async -> Bool
    func nextEvent(from: Date, within seconds: TimeInterval) async -> NextEvent?
}

/// Production reader backed by EventKit.
struct SystemCalendarReader: CalendarReading {
    func requestAccess() async -> Bool {
        #if canImport(EventKit)
        let store = EKEventStore()
        return await withCheckedContinuation { continuation in
            let handler: (Bool, Error?) -> Void = { granted, _ in continuation.resume(returning: granted) }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { granted, error in handler(granted, error) }
            } else {
                store.requestAccess(to: .event) { granted, error in handler(granted, error) }
            }
        }
        #else
        return false
        #endif
    }

    func nextEvent(from now: Date, within seconds: TimeInterval) async -> NextEvent? {
        #if canImport(EventKit)
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(seconds), calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        guard let event = upcoming.first else { return nil }
        return NextEvent(title: event.title ?? "Event", startsAt: event.startDate, isAllDay: event.isAllDay)
        #else
        return nil
        #endif
    }
}
