import Foundation

/// A module's typed state at a moment in time, paired with how much we trust it.
///
/// Modules emit a stream of `Snapshot`s; the shell renders them. Because
/// `freshness` is part of the value the module is *required* to return, it is
/// impossible to render a value without also stating how trustworthy it is.
public struct Snapshot<Value: Sendable>: Sendable {
    public let value: Value
    public let freshness: Freshness
    /// When the underlying value was confirmed by its source.
    public let asOf: Date

    public init(value: Value, freshness: Freshness, asOf: Date) {
        self.value = value
        self.freshness = freshness
        self.asOf = asOf
    }

    /// Transform the wrapped value, keeping freshness and timing intact.
    public func map<T: Sendable>(_ transform: (Value) -> T) -> Snapshot<T> {
        Snapshot<T>(value: transform(value), freshness: freshness, asOf: asOf)
    }
}
