import Foundation
import PerchCore
import PerchModuleKit

/// A short rolling history of a percentage gauge, so the panel can draw a trend.
public struct VitalSeries: Sendable, Equatable {
    public var current: Int
    public var history: [Int]   // oldest → newest

    public static let empty = VitalSeries(current: 0, history: [])
}

/// A fully local, zero-setup module: system CPU usage. The pill shows the
/// current value (green/amber/red); the panel shows a small trend sparkline —
/// so a runaway build is visible as a rising line, not just a number.
public struct VitalsModule: NotchModule {
    public typealias State = VitalSeries

    public static let descriptor = ModuleDescriptor(
        id: "system.cpu",
        name: "CPU",
        summary: "System CPU usage, sampled locally.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<VitalSeries>> {
        let clock = context.clock
        let interval = context.refreshSeconds(fallback: 2, minimum: 1)
        return AsyncStream { continuation in
            let reader = CPUReader()
            var history: [Int] = []
            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    if let percent = reader.sampleBusyPercent() {
                        let value = Int(percent.rounded())
                        history.append(value)
                        if history.count > 40 { history.removeFirst(history.count - 40) }
                        let now = clock.now()
                        continuation.yield(Snapshot(value: VitalSeries(current: value, history: history),
                                                    freshness: .live, asOf: now))
                    }
                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: VitalSeries, in slot: Slot) -> PillFace {
        vitalFace(label: "CPU", symbol: "cpu", percent: value.current, warn: 70)
    }

    public func detail(for value: VitalSeries) -> [DetailRow] {
        [vitalDetailRow(id: "cpu", label: "CPU", percent: value.current, history: value.history, warn: 70)]
    }
}

/// Shared pill styling for a percentage vital.
func vitalFace(label: String, symbol: String, percent: Int, warn: Int) -> PillFace {
    let tint: Tint = percent >= 90 ? .critical : (percent >= warn ? .warning : .good)
    return PillFace(text: "\(label) \(percent)%", symbolName: symbol, tint: tint,
                    tooltip: "\(label) \(percent)%")
}

/// Shared panel row (with a sparkline) for a percentage vital.
func vitalDetailRow(id: String, label: String, percent: Int, history: [Int], warn: Int) -> DetailRow {
    let tint: Tint = percent >= 90 ? .critical : (percent >= warn ? .warning : .good)
    return DetailRow(id: id, title: label, subtitle: "\(percent)%", tint: tint,
                     symbolName: nil, url: nil,
                     sparkline: history.isEmpty ? nil : history.map(Double.init))
}
