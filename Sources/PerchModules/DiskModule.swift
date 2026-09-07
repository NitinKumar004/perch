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

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<DiskSample>> {
        let path = context.settings["path"] ?? "/"
        return .periodic(every: context.refreshSeconds(fallback: 30, minimum: 5),
                         clock: context.clock, seed: .zero) {
            DiskReader.read(path: path)
        }
    }

    public func face(for value: DiskSample, in slot: Slot) -> PillFace {
        Self.face(for: value)
    }

    public func detail(for value: DiskSample) -> [DetailRow] {
        let f = Self.face(for: value)
        return [DetailRow(id: "disk", title: "Disk free",
                          subtitle: "\(ByteFormat.storage(UInt64(max(0, value.freeBytes)))) free · \(value.usedPercent)% used",
                          tint: f.tint, symbolName: "externaldrive")]
    }

    public func notification(for value: DiskSample, previous: DiskSample?) -> ModuleAlert? {
        guard value.usedPercent >= 90, let previous, previous.usedPercent < 90 else { return nil }
        // Distinct id per rising edge so refilling the disk later re-warns.
        return ModuleAlert(id: "disk-low-\(AlertEpisode.token())", title: "Disk almost full",
                           body: "\(ByteFormat.storage(UInt64(max(0, value.freeBytes)))) free — free space to avoid slowdowns.")
    }

    static func face(for sample: DiskSample) -> PillFace {
        let free = ByteFormat.storage(UInt64(max(0, sample.freeBytes)))
        return PillFace(text: "Disk \(free)", symbolName: "externaldrive",
                        tint: tint(sample.usedPercent),
                        tooltip: "\(free) free · \(sample.usedPercent)% used")
    }
    /// Under 85% used is fine, 85–95% getting tight, over 95% critical.
    static func tint(_ usedPercent: Int) -> Tint {
        // Disk fills later than CPU/RAM, so warn/critical sit higher.
        Tint.forUsage(percent: usedPercent, warn: 85, critical: 95)
    }
}
