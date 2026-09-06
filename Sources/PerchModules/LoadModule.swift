import Foundation
import Darwin
import PerchCore
import PerchModuleKit

/// A snapshot of system load: the 1-minute load average and the core count, so
/// the module can express load *per core* — the "is the system oversubscribed"
/// gauge (like `uptime`). Above ~1.0 per core the Mac is fully committed; well
/// above it, things get sluggish and can hang.
public struct LoadSample: Sendable, Equatable {
    public var oneMinute: Double
    public var cores: Int
    public var ratio: Double { cores > 0 ? oneMinute / Double(cores) : 0 }
    public static let zero = LoadSample(oneMinute: 0, cores: 1)
}

/// Reads the 1-minute load average via `getloadavg`.
enum LoadReader {
    static func read() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        guard count > 0 else { return nil }
        return loads[0]
    }
}

public struct LoadModule: NotchModule {
    public typealias State = LoadSample

    public static let descriptor = ModuleDescriptor(
        id: "system.load",
        name: "Load average",
        summary: "System load per CPU core — how oversubscribed the Mac is.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<LoadSample>> {
        let clock = context.clock
        let interval = context.refreshSeconds(fallback: 3, minimum: 1)
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(Snapshot(value: .zero, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    if let one = LoadReader.read() {
                        continuation.yield(Snapshot(value: LoadSample(oneMinute: one, cores: cores),
                                                    freshness: .live, asOf: clock.now()))
                    }
                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: LoadSample, in slot: Slot) -> PillFace {
        Self.face(for: value)
    }

    public func detail(for value: LoadSample) -> [DetailRow] {
        let f = Self.face(for: value)
        return [DetailRow(id: "load", title: "Load average",
                          subtitle: String(format: "%.2f over %d cores", value.oneMinute, value.cores),
                          tint: f.tint, symbolName: "speedometer")]
    }

    static func face(for sample: LoadSample) -> PillFace {
        PillFace(text: String(format: "Load %.1f", sample.oneMinute),
                 symbolName: "speedometer", tint: tint(sample.ratio),
                 tooltip: String(format: "1-min load %.2f · %d cores", sample.oneMinute, sample.cores))
    }
    /// Per-core load: under ~0.7 comfortable, up to ~1.0 fully busy, above → overloaded.
    static func tint(_ ratio: Double) -> Tint {
        if ratio >= 1.0 { return .critical }
        if ratio >= 0.7 { return .warning }
        return .good
    }
}
