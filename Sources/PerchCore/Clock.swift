import Foundation

/// An abstraction over "now" so time-dependent logic (staleness, TTLs) can be
/// tested deterministically instead of sleeping in tests.
public protocol Clock: Sendable {
    func now() -> Date
}

/// The real wall clock used in production.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
