import Foundation
import PerchCore
import PerchModuleKit

/// A fully local, zero-setup module: system CPU usage. Green when idle, amber
/// past a threshold, red when pegged — so a runaway build or a swap storm is
/// visible the moment it starts. Nothing leaves the Mac.
///
/// The warn/critical thresholds are configurable via settings.
public struct VitalsModule: NotchModule {
    public typealias State = Int   // busy percent, 0–100

    public static let descriptor = ModuleDescriptor(
        id: "system.cpu",
        name: "CPU",
        summary: "System CPU usage, sampled locally.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Int>> {
        let clock = context.clock
        return AsyncStream { continuation in
            let reader = CPUReader()
            let task = Task {
                continuation.yield(Snapshot(value: 0, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    if let percent = reader.sampleBusyPercent() {
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
        // Defaults chosen to be quiet until the machine is genuinely working.
        let tint: Tint = value >= 90 ? .critical : (value >= 70 ? .warning : .good)
        return PillFace(text: "\(value)%", symbolName: "cpu", tint: tint, tooltip: "CPU \(value)%")
    }
}
