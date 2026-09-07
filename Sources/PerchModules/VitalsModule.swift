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
        let reader = CPUReader()
        return vitalSeriesStream(every: context.refreshSeconds(fallback: 2, minimum: 1),
                                 clock: context.clock) { reader.sampleBusyPercent() }
    }

    public func face(for value: VitalSeries, in slot: Slot) -> PillFace {
        vitalFace(label: "CPU", symbol: "cpu", percent: value.current, warn: 70)
    }

    public func detail(for value: VitalSeries) -> [DetailRow] {
        [vitalDetailRow(id: "cpu", label: "CPU", percent: value.current, history: value.history, warn: 70)]
    }
}

/// Shared rolling-percentage stream for CPU/RAM-style vitals: seeds `.empty`,
/// then each tick samples a percentage, appends it to a capped history, and
/// yields a `VitalSeries` (current + sparkline history). One home for the
/// stateful-history pattern CPU and Memory both use — the genuinely-stateful
/// counterpart to `AsyncStream.periodic`.
func vitalSeriesStream(
    every interval: Double, clock: any Clock, cap: Int = 40,
    sample: @escaping @Sendable () -> Double?
) -> AsyncStream<Snapshot<VitalSeries>> {
    AsyncStream { continuation in
        var history: [Int] = []
        let task = Task {
            continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))
            while !Task.isCancelled {
                if let percent = sample() {
                    let value = Int(percent.rounded())
                    history.append(value)
                    if history.count > cap { history.removeFirst(history.count - cap) }
                    continuation.yield(Snapshot(value: VitalSeries(current: value, history: history),
                                                freshness: .live, asOf: clock.now()))
                }
                try? await Task.sleep(for: .seconds(interval))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Shared pill styling for a percentage vital.
func vitalFace(label: String, symbol: String, percent: Int, warn: Int) -> PillFace {
    let tint = Tint.forUsage(percent: percent, warn: warn)
    return PillFace(text: "\(label) \(percent)%", symbolName: symbol, tint: tint,
                    tooltip: "\(label) \(percent)%")
}

/// Shared panel row (with a sparkline) for a percentage vital.
func vitalDetailRow(id: String, label: String, percent: Int, history: [Int], warn: Int) -> DetailRow {
    let tint = Tint.forUsage(percent: percent, warn: warn)
    return DetailRow(id: id, title: label, subtitle: "\(percent)%", tint: tint,
                     symbolName: nil, url: nil,
                     sparkline: history.isEmpty ? nil : history.map(Double.init))
}
