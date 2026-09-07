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
        vitalSeriesStream(every: context.refreshSeconds(fallback: 2, minimum: 1),
                          clock: context.clock) { MemoryReader.usedPercent() }
    }

    public func face(for value: VitalSeries, in slot: Slot) -> PillFace {
        vitalFace(label: "RAM", symbol: "memorychip", percent: value.current, warn: 75)
    }

    public func detail(for value: VitalSeries) -> [DetailRow] {
        [vitalDetailRow(id: "ram", label: "RAM", percent: value.current, history: value.history, warn: 75)]
    }
}
