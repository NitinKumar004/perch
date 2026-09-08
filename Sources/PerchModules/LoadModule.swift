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

    private let thresholds: MetricThresholds

    public init(thresholds: MetricThresholds = .standard) { self.thresholds = thresholds }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<LoadSample>> {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return .periodic(every: context.refreshSeconds(fallback: 3, minimum: 1),
                         clock: context.clock, seed: .zero) {
            LoadReader.read().map { LoadSample(oneMinute: $0, cores: cores) }
        }
    }

    public func face(for value: LoadSample, in slot: Slot) -> PillFace {
        faceFor(value)
    }

    public func detail(for value: LoadSample) -> [DetailRow] {
        return [DetailRow(id: "load", title: "Load average",
                          subtitle: String(format: "%.2f over %d cores", value.oneMinute, value.cores),
                          tint: thresholds.loadTint(ratio: value.ratio), symbolName: "speedometer")]
    }

    private func faceFor(_ sample: LoadSample) -> PillFace {
        PillFace(text: String(format: "Load %.1f", sample.oneMinute),
                 symbolName: "speedometer", tint: thresholds.loadTint(ratio: sample.ratio),
                 tooltip: String(format: "1-min load %.2f · %d cores", sample.oneMinute, sample.cores))
    }
}
