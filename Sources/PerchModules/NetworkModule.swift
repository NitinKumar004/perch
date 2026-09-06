import Foundation
import PerchCore
import PerchModuleKit

/// Down/up throughput at a moment, derived from the delta between two reads.
public struct NetThroughput: Sendable, Equatable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double
    public static let zero = NetThroughput(downBytesPerSec: 0, upBytesPerSec: 0)
}

/// A fully local, zero-setup module: network throughput. The pill shows the
/// download rate (what people watch during a slow deploy or a big pull); the
/// panel breaks out down and up. Configurable refresh interval.
public struct NetworkModule: NotchModule {
    public typealias State = NetThroughput

    public static let descriptor = ModuleDescriptor(
        id: "system.network",
        name: "Network",
        summary: "Download / upload throughput, sampled locally.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<NetThroughput>> {
        let clock = context.clock
        let interval = context.refreshSeconds(fallback: 2, minimum: 1)
        return AsyncStream { continuation in
            var previous = NetworkReader.totalBytes()
            let task = Task {
                continuation.yield(Snapshot(value: .zero, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    guard let current = NetworkReader.totalBytes() else { continue }
                    defer { previous = current }
                    guard let prev = previous,
                          current.inBytes >= prev.inBytes,   // skip counter wrap
                          current.outBytes >= prev.outBytes else { continue }
                    let down = Double(current.inBytes - prev.inBytes) / interval
                    let up = Double(current.outBytes - prev.outBytes) / interval
                    continuation.yield(Snapshot(value: NetThroughput(downBytesPerSec: down, upBytesPerSec: up),
                                                freshness: .live, asOf: clock.now()))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: NetThroughput, in slot: Slot) -> PillFace {
        PillFace(text: "↓ \(NetworkReader.humanRate(value.downBytesPerSec))",
                 symbolName: "network", tint: .neutral,
                 tooltip: "↓ \(NetworkReader.humanRate(value.downBytesPerSec)) · ↑ \(NetworkReader.humanRate(value.upBytesPerSec))")
    }

    public func detail(for value: NetThroughput) -> [DetailRow] {
        [
            DetailRow(id: "net-down", title: "Download",
                      subtitle: NetworkReader.humanRate(value.downBytesPerSec),
                      tint: .info, symbolName: "arrow.down.circle"),
            DetailRow(id: "net-up", title: "Upload",
                      subtitle: NetworkReader.humanRate(value.upBytesPerSec),
                      tint: .neutral, symbolName: "arrow.up.circle"),
        ]
    }
}
