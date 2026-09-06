import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// PR-queue state: the count drives the pill, the list drives the panel.
public struct PRState: Sendable, Equatable {
    public var count: Int
    public var items: [PRSummary]
    /// The repo this is scoped to (nil = all repos) — so an empty result can
    /// explain itself honestly.
    public var repoScope: String?
    /// User-chosen display toggles.
    public var showChecks: Bool
    public var showReview: Bool

    public init(count: Int, items: [PRSummary], repoScope: String? = nil,
                showChecks: Bool = true, showReview: Bool = true) {
        self.count = count
        self.items = items
        self.repoScope = repoScope
        self.showChecks = showChecks
        self.showReview = showReview
    }

    public static let empty = PRState(count: 0, items: [], repoScope: nil)
}

/// Shows your pull-request review queue — the count of PRs waiting on your
/// review on a pill, and the actual list (clickable) in the panel. Configurable
/// via settings: `queue` (review-requested | author) and an optional `repo`.
public struct GitHubPRsModule: NotchModule {
    public typealias State = PRState

    public static let descriptor = ModuleDescriptor(
        id: "github.prs",
        name: "Pull requests",
        summary: "How many PRs are waiting on your review.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: true
    )

    private let client: GitHubAPIClient

    public init(client: GitHubAPIClient) {
        self.client = client
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<PRState>> {
        let clock = context.clock
        let client = client
        let queue = PRQueue(rawValue: context.settings["queue"] ?? "") ?? .reviewRequested
        let repo = context.settings["repo"]
        let interval = context.refreshSeconds(fallback: 90, minimum: 30)
        let limit = context.int("limit", fallback: 8, minimum: 1, maximum: 25)
        let showChecks = context.bool("showChecks", fallback: true)
        let showReview = context.bool("showReview", fallback: true)

        return AsyncStream { continuation in
            let store = VersionedStore<String, PRState>(clock: clock)
            let key = "\(queue.rawValue)#\(repo ?? "*")"
            var lastError: String?   // so a repeating error is logged once, not every poll
            var failures = 0
            let backoff = Backoff(base: 15, cap: 300)

            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = interval
                    do {
                        let observation = try await client.pullRequestList(queue: queue, repo: repo, limit: limit, now: clock.now())
                        if lastError != nil { print("[perch] pr poll \(key): recovered"); lastError = nil }
                        failures = 0
                        let state = PRState(count: observation.total, items: observation.items,
                                            repoScope: repo, showChecks: showChecks, showReview: showReview)
                        let accepted = await store.apply(state, forKey: key, version: observation.observedAt)
                        if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                            continuation.yield(snapshot)
                        }
                    } catch {
                        failures += 1
                        let desc = "\(error)"
                        if lastError != desc { print("[perch] pr poll \(key): error \(desc)"); lastError = desc }
                        // A 4xx on a repo-scoped query means the current credential
                        // can't see that repo — a private repo the GitHub App isn't
                        // installed on (GitHub returns 422 for that). Show the honest
                        // "needs access" hint instead of an error loop, and stop
                        // hammering it (it won't change until the user acts).
                        if case GitHubAuthError.http(let status) = error,
                           (400..<500).contains(status), let repo {
                            let noAccess = PRState(count: 0, items: [], repoScope: repo)
                            continuation.yield(Snapshot(value: noAccess, freshness: .unknown, asOf: clock.now()))
                            nextDelay = backoff.cap
                        } else if let stale = await store.snapshot(forKey: key, ttl: 0) {
                            continuation.yield(stale)
                            nextDelay = backoff.delay(consecutiveFailures: failures)
                        } else {
                            continuation.yield(Snapshot(value: .empty, freshness: .error("\(error)"), asOf: clock.now()))
                            nextDelay = backoff.delay(consecutiveFailures: failures)
                        }
                    }
                    try? await Task.sleep(for: .seconds(nextDelay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: PRState, in slot: Slot) -> PillFace {
        if value.count == 0 {
            return PillFace(text: "PR", symbolName: "checkmark.seal", tint: .neutral,
                            tooltip: "No PRs waiting on you")
        }
        return PillFace(text: "\(value.count)", symbolName: "arrow.triangle.pull",
                        tint: .warning, tooltip: "\(value.count) PR\(value.count == 1 ? "" : "s") waiting on your review")
    }

    public func notification(for value: PRState, previous: PRState?) -> ModuleAlert? {
        // Alert when the review queue grows — a new PR is waiting on you.
        guard let previous, value.count > previous.count else { return nil }
        let newest = value.items.first
        return ModuleAlert(
            id: "prs-\(value.count)-\(newest?.number ?? 0)",
            title: "Review requested",
            body: newest.map { "#\($0.number) \($0.title)" }
                ?? "\(value.count) PR\(value.count == 1 ? "" : "s") waiting on you",
            url: newest?.url)
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let scope = context.settings["repo"].flatMap { $0.isEmpty ? nil : $0 } ?? "all repos"
        let which = (context.settings["queue"] == "author") ? "opened by me" : "my review"
        return "\(scope) · \(which)"
    }

    public func detail(for value: PRState) -> [DetailRow] {
        if value.items.isEmpty {
            // Nothing to list. If scoped to a repo and empty, explain the most
            // common cause honestly — a private repo Perch can't see yet.
            if value.count == 0, let scope = value.repoScope {
                return [DetailRow(
                    id: "pr-none",
                    title: "No matching PRs in \(scope)",
                    subtitle: "Private repo? Tap to grant Perch access on GitHub — or sign in with a token in Settings.",
                    tint: .neutral, symbolName: "lock.circle",
                    url: "https://github.com/settings/installations")]
            }
            return value.count == 0 ? [] : [DetailRow(id: "pr-empty", title: "\(value.count) waiting", tint: .warning)]
        }
        return value.items.map { pr in
            let review = Self.status(for: pr)
            let ci = value.showChecks ? Self.ciStatus(pr.checksState, done: pr.checksDone, total: pr.checksTotal) : nil
            // Subtitle names the source, plus whichever of CI / review the user
            // chose to show; the row escalates to red if CI is failing.
            let parts = [pr.repo, ci?.label, value.showReview ? review.label : nil].compactMap { $0 }
            let tint: Tint = (ci?.tint == .critical) ? .critical : (value.showReview ? review.tint : .info)
            return DetailRow(
                id: "pr-\(pr.repo)-\(pr.number)",
                title: "#\(pr.number) \(pr.title)",
                subtitle: parts.joined(separator: " · "),
                tint: tint,
                symbolName: review.symbol,
                url: pr.url,
                progress: ci?.progress)
        }
    }

    /// Map a PR's review + merge status to a label, tint, and icon.
    static func status(for pr: PRSummary) -> (label: String, tint: Tint, symbol: String) {
        if pr.isDraft { return ("draft", .neutral, "pencil.circle") }
        if pr.mergeable == "CONFLICTING" { return ("conflicts", .critical, "exclamationmark.triangle.fill") }
        switch pr.reviewDecision {
        case "APPROVED":          return ("approved", .good, "checkmark.circle.fill")
        case "CHANGES_REQUESTED": return ("changes requested", .critical, "xmark.circle.fill")
        case "REVIEW_REQUIRED":   return ("review required", .warning, "clock.fill")
        default:                  return ("open", .info, "arrow.triangle.pull")
        }
    }

    /// Map a PR's CI checks rollup to a short label, tint, and completion fraction
    /// — the "why is the pipeline running / how far along" signal. When a run is
    /// in flight and we know the counts, the label reads "CI 5/10" and `progress`
    /// drives a thin bar; otherwise it's a plain passing/failing/running badge.
    static func ciStatus(_ state: String?, done: Int = 0, total: Int = 0)
        -> (label: String, tint: Tint, progress: Double?)? {
        let fraction = total > 0 ? Double(done) / Double(total) : nil
        switch state {
        case "SUCCESS":            return ("CI passing", .good, nil)
        case "FAILURE", "ERROR":   return ("CI failing", .critical, fraction)
        case "PENDING":
            if total > 0 { return ("CI \(done)/\(total)", .info, fraction) }
            return ("CI running", .info, nil)
        default:                   return nil   // no checks / expected — don't clutter
        }
    }
}
