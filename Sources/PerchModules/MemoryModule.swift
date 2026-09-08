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

    private let thresholds: MetricThresholds

    public init(thresholds: MetricThresholds = .standard) { self.thresholds = thresholds }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<VitalSeries>> {
        vitalSeriesStream(every: context.refreshSeconds(fallback: 2, minimum: 1),
                          clock: context.clock) { MemoryReader.usedPercent() }
    }

    public func face(for value: VitalSeries, in slot: Slot) -> PillFace {
        vitalFace(label: "RAM", symbol: "memorychip", percent: value.current,
                  tint: thresholds.memoryTint(value.current))
    }

    public func detail(for value: VitalSeries) -> [DetailRow] {
        [vitalDetailRow(id: "ram", label: "RAM", percent: value.current, history: value.history,
                        tint: thresholds.memoryTint(value.current))]
    }

    /// Notify when memory stays critically high — the actionable "about to swap
    /// and thrash" signal. Sustained (not a brief spike) so it's never noise; CPU
    /// and load are deliberately left visual-only, since they peg during normal
    /// builds and would notify constantly.
    public func notification(for value: VitalSeries, previous: VitalSeries?) -> ModuleAlert? {
        sustainedVitalAlert(label: "Memory", idPrefix: "memory", value: value,
                            critical: thresholds.memoryCritical)
    }
}
