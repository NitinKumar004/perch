import Testing
import Foundation
import PerchCore
@testable import PerchSync

/// A clock the test controls, so staleness is verified deterministically
/// instead of by sleeping.
final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        current = start
    }

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(interval); lock.unlock()
    }
}

private let v100 = Date(timeIntervalSince1970: 100)
private let v200 = Date(timeIntervalSince1970: 200)

@Test func acceptsNewerRejectsOlderAndDuplicate() async {
    let store = VersionedStore<String, String>(clock: TestClock())

    #expect(await store.apply("a", forKey: "k", version: v100) == true)   // first write
    #expect(await store.apply("b", forKey: "k", version: v200) == true)   // strictly newer
    #expect(await store.apply("stale", forKey: "k", version: v100) == false) // out-of-order
    #expect(await store.apply("dup", forKey: "k", version: v200) == false)   // duplicate

    let value = await store.snapshot(forKey: "k", ttl: 3600)?.value
    #expect(value == "b") // state never moves backwards
}

@Test func freshnessGoesStaleAfterTTL() async {
    let clock = TestClock()
    let confirmedAt = clock.now()   // when the value is received/confirmed
    let store = VersionedStore<String, Int>(clock: clock)

    _ = await store.apply(7, forKey: "cpu", version: v100)

    let live = await store.snapshot(forKey: "cpu", ttl: 60)
    #expect(live?.freshness == .live)

    clock.advance(by: 120) // now older than the 60s TTL

    let stale = await store.snapshot(forKey: "cpu", ttl: 60)
    // Staleness is measured from confirmation time, not the source version.
    #expect(stale?.freshness == .stale(since: confirmedAt))
    #expect(stale?.value == 7) // a stale value is still the last known value
}

@Test func unknownKeyReturnsNil() async {
    let store = VersionedStore<String, Int>(clock: TestClock())
    let missing = await store.snapshot(forKey: "nope", ttl: 60)
    #expect(missing == nil)
}
