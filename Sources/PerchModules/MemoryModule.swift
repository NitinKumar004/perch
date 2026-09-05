import Foundation
import PerchCore
import PerchModuleKit

/// A fully local, zero-setup module: system memory (RAM) usage. Distinct from
/// CPU — its own icon and a `RAM` label — with a trend sparkline in the panel.
public struct MemoryModule: NotchModule {
    public typealias State = VitalSeries

    public static let descriptor = ModuleDescriptor(
        id: "system.memory",
        name: "Memory",
        summary: "System memory (RAM) in use, sampled locally.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<VitalSeries>> {
        let clock = context.clock
        return AsyncStream { continuation in
            var history: [Int] = []
            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    if let percent = MemoryReader.usedPercent() {
                        let value = Int(percent.rounded())
                        history.append(value)
                        if history.count > 40 { history.removeFirst(history.count - 40) }
                        let now = clock.now()
                        continuation.yield(Snapshot(value: VitalSeries(current: value, history: history),
                                                    freshness: .live, asOf: now))
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: VitalSeries, in slot: Slot) -> PillFace {
        vitalFace(label: "RAM", symbol: "memorychip", percent: value.current, warn: 75)
    }

    public func detail(for value: VitalSeries) -> [DetailRow] {
        [vitalDetailRow(id: "ram", label: "RAM", percent: value.current, history: value.history, warn: 75)]
    }
}
