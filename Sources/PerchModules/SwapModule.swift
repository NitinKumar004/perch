import Foundation
import PerchCore
import PerchModuleKit

/// A fully local, zero-setup module: swap usage. When the Mac runs low on RAM it
/// pushes memory to disk (swap); heavy, growing swap is *the* early sign of the
/// beachball/thrash that precedes a freeze — more predictive than plain RAM %.
public struct SwapModule: NotchModule {
    public typealias State = UInt64   // swap used, in bytes

    public static let descriptor = ModuleDescriptor(
        id: "system.swap",
        name: "Swap",
        summary: "Swap in use — an early warning before the Mac starts thrashing.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let thresholds: MetricThresholds

    public init(thresholds: MetricThresholds = .standard) { self.thresholds = thresholds }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<UInt64>> {
        .periodic(every: context.refreshSeconds(fallback: 3, minimum: 1),
                  clock: context.clock, seed: 0) {
            MemoryReader.swapUsedBytes()
        }
    }

    public func face(for value: UInt64, in slot: Slot) -> PillFace {
        faceFor(value)
    }

    public func detail(for value: UInt64) -> [DetailRow] {
        return [DetailRow(id: "swap", title: "Swap used",
                          subtitle: value == 0 ? "none — healthy" : ByteFormat.size(value),
                          tint: thresholds.swapTint(bytes: value), symbolName: "internaldrive")]
    }

    public func notification(for value: UInt64, previous: UInt64?) -> ModuleAlert? {
        // Warn once when swap first climbs past the user's critical level.
        let heavy = thresholds.swapCriticalBytes
        guard value >= heavy, let previous, previous < heavy else { return nil }
        // Distinct id per rising edge so a later swap spike isn't deduped away.
        return ModuleAlert(id: "swap-heavy-\(AlertEpisode.token())", title: "Memory pressure is high",
                           body: "\(ByteFormat.size(value)) of swap in use — the Mac may start to stall.")
    }

    private func faceFor(_ bytes: UInt64) -> PillFace {
        PillFace(text: bytes == 0 ? "Swap 0" : "Swap \(ByteFormat.size(bytes))",
                 symbolName: "internaldrive", tint: thresholds.swapTint(bytes: bytes),
                 tooltip: bytes == 0 ? "No swap in use" : "\(ByteFormat.size(bytes)) of swap in use")
    }
}
