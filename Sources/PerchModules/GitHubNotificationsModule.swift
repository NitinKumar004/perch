import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// Your GitHub notification inbox — the count of unread threads on the pill, and
/// the actual list (mention, review request, CI, …), click-to-open, in the panel.
public struct NotificationState: Sendable, Equatable {
    public var items: [NotificationThread]
    /// True when GitHub had more than the fetched page (50) of unread threads, so
    /// the count is a floor — the UI shows "N+".
    public var truncated: Bool
    public var count: Int { items.count }
    /// "N+" when truncated, else "N".
    public var countLabel: String { truncated ? "\(count)+" : "\(count)" }

    public init(items: [NotificationThread], truncated: Bool = false) {
        self.items = items
        self.truncated = truncated
    }
    public static let empty = NotificationState(items: [])
}

/// The "GitHub bell" in the notch. Polls the notifications REST endpoint with a
/// conditional ETag (304s are free and honour GitHub's poll etiquette), routes
/// each snapshot through `VersionedStore` for honest freshness, and surfaces the
/// unread count + a click-to-open list.
public struct GitHubNotificationsModule: NotchModule {
    public typealias State = NotificationState

    public static let descriptor = ModuleDescriptor(
        id: "github.notifications",
        name: "Notifications",
        summary: "Your unread GitHub notifications — mentions, review requests, CI.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: true,
        detailFirst: true,          // a list you act on — surface it in the panel
        opensPanelOnCritical: false // an inbox to triage, not a live incident
    )

    private let client: GitHubAPIClient

    public init(client: GitHubAPIClient) { self.client = client }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<NotificationState>> {
        let clock = context.clock
        let client = client
        let interval = context.refreshSeconds(fallback: 60, minimum: 30)

        return AsyncStream { continuation in
            let store = VersionedStore<String, NotificationState>(clock: clock)
            let key = "notifications"
            var etag: String?
            var failures = 0
            let backoff = Backoff(base: 15, cap: 300)
            var lastLog: String?

            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))
                while !Task.isCancelled {
                    var nextDelay = interval
                    // Respect the shared rate-limit budget so several GitHub pollers
                    // running together back off in concert before hitting a 403.
                    let throttle = await client.rateLimit.throttleDelay()
                    if throttle > 0 { try? await Task.sleep(for: .seconds(min(throttle, 60))) }
                    do {
                        let fetch = try await client.notifications(etag: etag)
                        failures = 0
                        switch fetch {
                        case .notModified:
                            break   // free 304 — nothing changed
                        case .ok(let threads, let newEtag, let truncated):
                            etag = newEtag
                            let state = NotificationState(items: threads, truncated: truncated)
                            let line = "\(state.count) unread"
                            if lastLog != line { print("[perch] notifications: \(line)"); lastLog = line }
                            // Monotonic version (now) so the latest fetch always
                            // wins — a wholesale list, including "now empty".
                            if await store.apply(state, forKey: key, version: clock.now()),
                               let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                                continuation.yield(snapshot)
                            }
                        }
                    } catch {
                        failures += 1
                        let line = "error \(error)"
                        if lastLog != line { print("[perch] notifications: \(line)"); lastLog = line }
                        if let stale = await store.snapshot(forKey: key, ttl: 0) {
                            continuation.yield(stale)
                        } else {
                            continuation.yield(Snapshot(value: .empty, freshness: .error("\(error)"), asOf: clock.now()))
                        }
                        nextDelay = Self.isAuthError(error) ? backoff.cap : backoff.delay(consecutiveFailures: failures)
                    }
                    try? await Task.sleep(for: .seconds(nextDelay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: NotificationState, in slot: Slot) -> PillFace {
        guard value.count > 0 else {
            return PillFace(text: "0", symbolName: "bell", tint: .neutral,
                            tooltip: "No unread notifications")
        }
        let plural = (value.count == 1 && !value.truncated) ? "" : "s"
        return PillFace(text: value.countLabel, symbolName: "bell.badge", tint: .warning,
                        tooltip: "\(value.countLabel) unread notification\(plural)")
    }

    public func detail(for value: NotificationState) -> [DetailRow] {
        value.items.map { n in
            DetailRow(
                id: "notif-\(n.id)",
                title: n.title.isEmpty ? n.repo : n.title,
                subtitle: "\(n.repo) · \(Self.friendlyReason(n.reason))",
                tint: Self.tint(for: n.reason),
                symbolName: Self.symbol(for: n.reason),
                url: n.htmlURL)
        }
    }

    public func notification(for value: NotificationState, previous: NotificationState?) -> ModuleAlert? {
        // Alert only on a genuinely NEW thread id (not a bigger count). The
        // cold-start "don't alert for pre-existing unread on launch" baseline is
        // handled universally by AnyNotchModule (it only diffs across live
        // observations), so this stays a simple new-vs-known diff.
        guard let previous else { return nil }
        let known = Set(previous.items.map(\.id))
        let fresh = value.items.filter { !known.contains($0.id) }
        guard let first = fresh.first else { return nil }
        // A single new thread names itself; a burst of several in one poll is
        // summarised in ONE notification ("… +N more") so none is silently
        // missed and the user isn't hit with a stack of banners at once. The id
        // carries the newest thread id (+ count) so it dedups but a later burst
        // still alerts.
        if fresh.count == 1 {
            return ModuleAlert(
                id: "gh-notif-\(first.id)",
                title: Self.friendlyReason(first.reason).capitalized,
                body: "\(first.repo): \(first.title)",
                url: first.htmlURL)
        }
        return ModuleAlert(
            id: "gh-notif-\(first.id)-\(fresh.count)",
            title: "\(fresh.count) new notifications",
            body: "\(first.repo): \(first.title)  +\(fresh.count - 1) more",
            url: first.htmlURL)
    }

    public func contextLabel(_ context: ModuleContext) -> String? { "unread on GitHub" }

    // MARK: - Reason presentation (pure)

    static func friendlyReason(_ reason: String) -> String {
        switch reason {
        case "mention", "team_mention": return "mentioned you"
        case "review_requested":        return "review requested"
        case "assign":                  return "assigned to you"
        case "ci_activity":             return "CI activity"
        case "comment":                 return "new comment"
        case "state_change":            return "state changed"
        case "author":                  return "your thread"
        case "subscribed":              return "update"
        case "security_alert":          return "security alert"
        default:                        return reason.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func tint(for reason: String) -> Tint {
        switch reason {
        case "security_alert":                        return .critical
        case "review_requested", "mention", "team_mention", "assign": return .warning
        case "ci_activity":                           return .info
        default:                                      return .neutral
        }
    }

    static func symbol(for reason: String) -> String {
        switch reason {
        case "mention", "team_mention": return "at"
        case "review_requested":        return "eye"
        case "assign":                  return "person.crop.circle"
        case "ci_activity":             return "checkmark.seal"
        case "comment":                 return "text.bubble"
        case "security_alert":          return "exclamationmark.shield"
        case "state_change":            return "arrow.triangle.merge"
        default:                        return "bell"
        }
    }

    static func isAuthError(_ error: Error) -> Bool {
        if case GitHubAuthError.notConnected = error { return true }
        if case GitHubAuthError.http(let status) = error { return status == 401 || status == 403 }
        return false
    }
}
