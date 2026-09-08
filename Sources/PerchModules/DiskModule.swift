import Foundation
import PerchCore
import PerchModuleKit

/// Free space on a volume. A near-full boot disk causes beachballs and hangs
/// (macOS needs headroom for swap and caches), so this is a quiet "before it
/// stalls" gauge. Defaults to the boot volume; `path` can point at another.
public struct DiskSample: Sendable, Equatable {
    public var freeBytes: Int64
    public var totalBytes: Int64
    public var usedPercent: Int {
        guard totalBytes > 0 else { return 0 }
        // "Available for important usage" counts purgeable space and can exceed
        // total, which would make used negative — clamp free to total, then 0…100.
        let free = min(max(0, freeBytes), totalBytes)
        let pct = Int((Double(totalBytes - free) / Double(totalBytes) * 100).rounded())
        return min(100, max(0, pct))
    }
    public static let zero = DiskSample(freeBytes: 0, totalBytes: 0)
}

/// Reads capacity for a volume via FileManager's resource values.
enum DiskReader {
    static func read(path: String) -> DiskSample? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) else { return nil }
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        guard let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return DiskSample(freeBytes: free, totalBytes: Int64(total))
    }
}

public struct DiskModule: NotchModule {
    public typealias State = DiskSample

    public static let descriptor = ModuleDescriptor(
        id: "system.disk",
        name: "Disk",
        summary: "Free space on your disk — low space causes beachballs.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let thresholds: MetricThresholds

    public init(thresholds: MetricThresholds = .standard) { self.thresholds = thresholds }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<DiskSample>> {
        let path = context.settings["path"] ?? "/"
        return .periodic(every: context.refreshSeconds(fallback: 30, minimum: 5),
                         clock: context.clock, seed: .zero) {
            DiskReader.read(path: path)
        }
    }

    public func face(for value: DiskSample, in slot: Slot) -> PillFace {
        faceFor(value)
    }

    public func detail(for value: DiskSample) -> [DetailRow] {
        return [DetailRow(id: "disk", title: "Disk free",
                          subtitle: "\(ByteFormat.storage(UInt64(max(0, value.freeBytes)))) free · \(value.usedPercent)% used",
                          tint: thresholds.diskTint(value.usedPercent), symbolName: "externaldrive")]
    }

    public func notification(for value: DiskSample, previous: DiskSample?) -> ModuleAlert? {
        let critical = thresholds.diskCritical
        guard value.usedPercent >= critical, let previous, previous.usedPercent < critical else { return nil }
        // Distinct id per rising edge so refilling the disk later re-warns.
        return ModuleAlert(id: "disk-low-\(AlertEpisode.token())", title: "Disk almost full",
                           body: "\(ByteFormat.storage(UInt64(max(0, value.freeBytes)))) free — free space to avoid slowdowns.")
    }

    private func faceFor(_ sample: DiskSample) -> PillFace {
        let free = ByteFormat.storage(UInt64(max(0, sample.freeBytes)))
        return PillFace(text: "Disk \(free)", symbolName: "externaldrive",
                        tint: thresholds.diskTint(sample.usedPercent),
                        tooltip: "\(free) free · \(sample.usedPercent)% used")
    }
}
