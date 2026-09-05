import Foundation
import PerchCore

/// The accuracy engine's core: a versioned, last-write-wins store keyed by a
/// monotonic version (a source timestamp).
///
/// This is what makes the "never a confident lie" promise concrete:
///
///  * **Ordering** — an incoming value is accepted only if it is *strictly
///    newer* than what we already hold, so out-of-order and duplicate delivery
///    can never move state backwards.
///  * **Freshness** — a value read back after its TTL is reported `.stale`
///    (carrying when it was last confirmed), never silently as live.
///
/// It is an `actor`, so concurrent providers and readers are safe without locks.
public actor VersionedStore<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        var value: Value
        var version: Date
        var receivedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let clock: any Clock

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    /// Apply an incoming value for `key`, stamped with its source `version`.
    ///
    /// - Returns: `true` if the value was newer and therefore stored; `false`
    ///   if it was stale or a duplicate and thus ignored.
    @discardableResult
    public func apply(_ value: Value, forKey key: Key, version: Date) -> Bool {
        if let existing = entries[key], version <= existing.version {
            return false // out-of-order or duplicate — drop it.
        }
        entries[key] = Entry(value: value, version: version, receivedAt: clock.now())
        return true
    }

    /// The current value for `key` together with an honest freshness given a
    /// staleness `ttl`. Returns `nil` if nothing has ever been stored.
    public func snapshot(forKey key: Key, ttl: TimeInterval) -> Snapshot<Value>? {
        guard let entry = entries[key] else { return nil }
        let age = clock.now().timeIntervalSince(entry.receivedAt)
        let freshness: Freshness = age > ttl ? .stale(since: entry.version) : .live
        return Snapshot(value: entry.value, freshness: freshness, asOf: entry.version)
    }

    /// The stored version for `key`, if any — useful for reconciliation to ask
    /// "do I already have something at least this new?".
    public func version(forKey key: Key) -> Date? {
        entries[key]?.version
    }
}
