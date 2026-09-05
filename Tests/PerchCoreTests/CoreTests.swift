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

@Test func snapshotMapPreservesFreshnessAndTiming() {
    let asOf = Date(timeIntervalSince1970: 500)
    let snapshot = Snapshot(value: 21, freshness: .stale(since: asOf), asOf: asOf)

    let mapped = snapshot.map { "\($0 * 2)" }

    #expect(mapped.value == "42")
    #expect(mapped.asOf == asOf)
    #expect(mapped.freshness == .stale(since: asOf))
}
