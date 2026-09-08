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

    private let thresholds: MetricThresholds

    public init(thresholds: MetricThresholds = .standard) { self.thresholds = thresholds }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<VitalSeries>> {
        let reader = CPUReader()
        return vitalSeriesStream(every: context.refreshSeconds(fallback: 2, minimum: 1),
                                 clock: context.clock) { reader.sampleBusyPercent() }
    }

    public func face(for value: VitalSeries, in slot: Slot) -> PillFace {
        vitalFace(label: "CPU", symbol: "cpu", percent: value.current, tint: thresholds.cpuTint(value.current))
    }

    public func detail(for value: VitalSeries) -> [DetailRow] {
        [vitalDetailRow(id: "cpu", label: "CPU", percent: value.current, history: value.history,
                        tint: thresholds.cpuTint(value.current))]
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

/// Shared pill styling for a percentage vital. The caller passes the tint it
/// resolved from the user's thresholds, so colour stays in one place per metric.
func vitalFace(label: String, symbol: String, percent: Int, tint: Tint) -> PillFace {
    PillFace(text: "\(label) \(percent)%", symbolName: symbol, tint: tint,
             tooltip: "\(label) \(percent)%")
}

/// A *sustained*-critical alert for a percentage vital, so a normal momentary
/// spike never notifies but a value that's genuinely stuck high does. Fires ONCE
/// at the moment the value has just stayed at/above `critical` for a run of
/// `sustain` samples, and only on a real below→sustained rising edge seen this
/// session (a value already maxed at launch stays silent — the sample before the
/// run must exist and be below critical). A later spell re-fires (fresh id). nil
/// otherwise.
func sustainedVitalAlert(label: String, idPrefix: String, value: VitalSeries,
                         critical: Int, sustain: Int = 5) -> ModuleAlert? {
    guard value.current >= critical else { return nil }
    let h = value.history
    guard h.count > sustain else { return nil }              // need a sample before the run
    guard h.suffix(sustain).allSatisfy({ $0 >= critical }) else { return nil }
    guard h[h.count - sustain - 1] < critical else { return nil }   // rising edge, not mid-spell
    return ModuleAlert(id: "\(idPrefix)-critical-\(AlertEpisode.token())",
                       title: "\(label) is running high",
                       body: "\(label) has stayed at \(value.current)% for a while — something's hogging it.")
}

/// Shared panel row (with a sparkline) for a percentage vital.
func vitalDetailRow(id: String, label: String, percent: Int, history: [Int], tint: Tint) -> DetailRow {
    DetailRow(id: id, title: label, subtitle: "\(percent)%", tint: tint,
              symbolName: nil, url: nil,
              sparkline: history.isEmpty ? nil : history.map(Double.init))
}
