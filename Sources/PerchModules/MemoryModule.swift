import Foundation
import PerchCore
import PerchModuleKit

/// A fully local, zero-setup module: system memory (RAM) usage. Distinct from
/// CPU — its own icon and a `RAM` label — so two vitals pills are never
/// confused. Green under pressure threshold, amber, then red.
public struct MemoryModule: NotchModule {
    public typealias State = Int   // used percent, 0–100

    public static let descriptor = ModuleDescriptor(
        id: "system.memory",
        name: "Memory",
        summary: "System memory (RAM) in use, sampled locally.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Int>> {
        let clock = context.clock
        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(Snapshot(value: 0, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    if let percent = MemoryReader.usedPercent() {
                        let now = clock.now()
                        continuation.yield(Snapshot(value: Int(percent.rounded()), freshness: .live, asOf: now))
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: Int, in slot: Slot) -> PillFace {
        let tint: Tint = value >= 90 ? .critical : (value >= 75 ? .warning : .good)
        return PillFace(text: "RAM \(value)%", symbolName: "memorychip", tint: tint, tooltip: "Memory \(value)% used")
    }
}
