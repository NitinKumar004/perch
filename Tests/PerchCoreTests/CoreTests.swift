import Testing
import Foundation
@testable import PerchCore

@Test func onlyLiveIsTrustworthy() {
    #expect(Freshness.live.isTrustworthy)
    #expect(!Freshness.computing.isTrustworthy)
    #expect(!Freshness.unknown.isTrustworthy)
    #expect(!Freshness.stale(since: Date()).isTrustworthy)
    #expect(!Freshness.error("boom").isTrustworthy)
}

@Test func semanticVersionComparesAndTolerates() {
    #expect(SemanticVersion.isNewer("v0.3.0", than: "0.2.0"))
    #expect(SemanticVersion.isNewer("1.0.0", than: "0.9.9"))
    #expect(SemanticVersion.isNewer("0.2.1", than: "0.2.0"))
    #expect(!SemanticVersion.isNewer("0.2.0", than: "0.2.0"))   // equal → not newer
    #expect(!SemanticVersion.isNewer("0.1.0", than: "0.2.0"))   // older
    #expect(SemanticVersion("1.2") == SemanticVersion("1.2.0")) // missing patch
    #expect(!SemanticVersion.isNewer("garbage", than: "0.2.0")) // unparseable → not newer
    #expect(!SemanticVersion.isNewer("v0.3.0", than: "dev"))    // bad base → not newer
}

@Test func snapshotMapPreservesFreshnessAndTiming() {
    let asOf = Date(timeIntervalSince1970: 500)
    let snapshot = Snapshot(value: 21, freshness: .stale(since: asOf), asOf: asOf)

    let mapped = snapshot.map { "\($0 * 2)" }

    #expect(mapped.value == "42")
    #expect(mapped.asOf == asOf)
    #expect(mapped.freshness == .stale(since: asOf))
}

@Test func usageTintCrossesThresholds() {
    // Default critical is 90 (CPU/RAM style).
    #expect(Tint.forUsage(percent: 10, warn: 70) == .good)
    #expect(Tint.forUsage(percent: 70, warn: 70) == .warning)
    #expect(Tint.forUsage(percent: 89, warn: 70) == .warning)
    #expect(Tint.forUsage(percent: 90, warn: 70) == .critical)
    // Disk-style higher thresholds.
    #expect(Tint.forUsage(percent: 84, warn: 85, critical: 95) == .good)
    #expect(Tint.forUsage(percent: 85, warn: 85, critical: 95) == .warning)
    #expect(Tint.forUsage(percent: 95, warn: 85, critical: 95) == .critical)
}

@Test func byteFormatSizesAndRates() {
    #expect(ByteFormat.size(0) == "0 B")
    #expect(ByteFormat.size(512 * 1024) == "512 KB")
    #expect(ByteFormat.size(UInt64(2.5 * 1_073_741_824)) == "2.5 GB")
    #expect(ByteFormat.rate(0) == "0 B/s")
    #expect(ByteFormat.rate(512) == "512 B/s")
    #expect(ByteFormat.rate(1536) == "1.5 KB/s")
    #expect(ByteFormat.rate(-10) == "0 B/s")   // never negative
}
