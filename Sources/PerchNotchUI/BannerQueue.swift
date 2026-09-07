import Foundation

/// Pure queueing for transient banners: at most one shows at a time, the rest
/// wait their turn. Kept separate from the timing (BannerPresenter) so the
/// ordering rules are testable without real timers.
public struct BannerQueue {
    public private(set) var current: BannerAlert?
    private var pending: [BannerAlert] = []

    public init() {}

    /// Queue a banner. Returns true if it should be shown immediately (nothing
    /// is currently showing), false if it was queued behind the current one.
    /// Ignores a banner whose id matches one already current/pending (the
    /// notifier dedups too, but this keeps the queue honest on its own).
    public mutating func enqueue(_ banner: BannerAlert) -> Bool {
        guard current?.id != banner.id, !pending.contains(where: { $0.id == banner.id }) else {
            return false
        }
        if current == nil {
            current = banner
            return true
        }
        pending.append(banner)
        return false
    }

    /// The current banner's time is up. Promotes the next pending banner (if any)
    /// to current and returns it, or nil when the queue is empty.
    public mutating func advance() -> BannerAlert? {
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }

    public var isEmpty: Bool { current == nil && pending.isEmpty }
    public var pendingCount: Int { pending.count }
}
