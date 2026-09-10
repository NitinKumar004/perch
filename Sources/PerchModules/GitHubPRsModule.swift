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
    /// The scoped repo couldn't be read (private repo Perch isn't installed on).
    /// Distinct from a genuine zero, so the pill can say so honestly.
    public var noAccess: Bool
    /// Which queue this state is for — so an empty result names the RIGHT reason
    /// ("none awaiting your review" vs "you haven't reviewed any"), instead of
    /// crying "grant access" on a query that actually succeeded.
    public var queue: PRQueue

    public init(count: Int, items: [PRSummary], repoScope: String? = nil,
                showChecks: Bool = true, showReview: Bool = true, noAccess: Bool = false,
                queue: PRQueue = .reviewRequested) {
        self.count = count
        self.items = items
        self.repoScope = repoScope
        self.showChecks = showChecks
        self.showReview = showReview
        self.noAccess = noAccess
        self.queue = queue
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
        requiresConnection: true,
        detailFirst: true,
        // A PR needing your review response is a to-do, not a live incident —
        // colour the pill red, but don't keep forcing the panel open for it.
        opensPanelOnCritical: false
    )

    private let client: GitHubAPIClient

    public init(client: GitHubAPIClient) {
        self.client = client
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<PRState>> {
        let clock = context.clock
        let client = client
        let queue = PRQueue(rawValue: context.settings["queue"] ?? "") ?? .reviewing
        // One repo, several (comma/space-separated), or blank = all accessible.
        let repos = parseRepoList(context.settings["repo"] ?? "")
        let scopeLabel = repos.isEmpty ? nil : repos.joined(separator: ", ")
        let interval = context.refreshSeconds(fallback: 90, minimum: 30)
        let limit = context.int("limit", fallback: 8, minimum: 1, maximum: 25)
        let showChecks = context.bool("showChecks", fallback: true)
        let showReview = context.bool("showReview", fallback: true)

        return AsyncStream { continuation in
            let store = VersionedStore<String, PRState>(clock: clock)
            let key = "\(queue.rawValue)#\(repos.joined(separator: "+").isEmpty ? "*" : repos.joined(separator: "+"))"
            var lastError: String?   // so a repeating error is logged once, not every poll
            var failures = 0
            let backoff = Backoff(base: 15, cap: 300)

            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = interval
                    // Respect the shared rate-limit budget so several GitHub pollers
                    // running together back off in concert before hitting a 403.
                    let throttle = await client.rateLimit.throttleDelay()
                    if throttle > 0 { try? await Task.sleep(for: .seconds(min(throttle, 60))) }
                    do {
                        let observation = try await Self.observe(queue, client: client, repos: repos, limit: limit, now: clock.now())
                        if lastError != nil { print("[perch] pr poll \(key): recovered"); lastError = nil }
                        failures = 0
                        let state = PRState(count: observation.total, items: observation.items,
                                            repoScope: scopeLabel, showChecks: showChecks, showReview: showReview,
                                            queue: queue)
                        let accepted = await store.apply(state, forKey: key, version: observation.observedAt)
                        if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                            continuation.yield(snapshot)
                        }
                        // While a PR's checks are still running, poll fast so the
                        // CI counter visibly climbs (0/22 → 5/22 → …) instead of
                        // sitting frozen and jumping straight to "passing".
                        let anyRunning = observation.items.contains { $0.checksState == "PENDING" }
                        nextDelay = anyRunning ? min(interval, 15) : interval
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
                           (400..<500).contains(status), let scope = scopeLabel {
                            let noAccess = PRState(count: 0, items: [], repoScope: scope, noAccess: true, queue: queue)
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
        if value.noAccess {
            // Can't see the scoped repo — say so, don't mimic a calm "0 PRs".
            return PillFace(text: "PR ?", symbolName: "lock", tint: .warning,
                            tooltip: "No access to \(value.repoScope ?? "that repo") — tap to grant Perch access")
        }
        if value.count == 0 {
            return PillFace(text: "PR", symbolName: "checkmark.seal", tint: .neutral,
                            tooltip: "No PRs waiting on you")
        }
        // The pill stays a calm glance: the PR count, plus a small attention dot
        // when you owe review responses. The exact number of threads lives in the
        // tooltip and in each panel row ("#2928 … · 12 to resolve") — no scary
        // figure shouting from the menu bar.
        let unresolved = value.items.reduce(0) { $0 + $1.unresolvedThreads }
        let base = "\(value.count) PR\(value.count == 1 ? "" : "s")"
        if unresolved > 0 {
            // "N+" when any PR had more threads than we fetched, so the tooltip
            // never claims an exact figure it didn't fully count.
            let more = value.items.contains { $0.moreThreads }
            let count = more ? "\(unresolved)+" : "\(unresolved)"
            return PillFace(
                text: "\(value.count)", symbolName: "arrow.triangle.pull", tint: .warning,
                tooltip: "\(base) · \(count) review thread\(unresolved == 1 && !more ? "" : "s") to resolve",
                badge: .critical)
        }
        return PillFace(text: "\(value.count)", symbolName: "arrow.triangle.pull",
                        tint: .warning, tooltip: "\(base) waiting on your review")
    }

    public func notification(for value: PRState, previous: PRState?) -> ModuleAlert? {
        // Tell the user when a watched PR *changes* — a merge conflict appears,
        // CI breaks, someone reviews/comments, it's approved — not only when a new
        // PR arrives. Surface the single most important change and summarise the
        // rest ("+N more"); stable ids keep the same state from re-nagging.
        guard let previous else { return nil }
        let changes = PRTransitions.detect(previous: previous.items, current: value.items,
                                           previousCount: previous.count, currentCount: value.count)
        guard let top = changes.max(by: { $0.kind < $1.kind }) else { return nil }
        let extra = changes.count - 1
        // Lead with the SIGNAL ("#2821 · changes requested"), not the PR title —
        // the banner marquees, so a long title would push the actual reason out of
        // view for several seconds ("empty then the message arrives"). Short,
        // signal-first text is fully readable the instant the banner appears; the
        // PR title trails as context.
        let more = extra > 0 ? "  ·  +\(extra) more" : ""
        return ModuleAlert(
            id: top.id,
            title: "#\(top.number) · \(top.phrase)\(more)",
            body: top.title,
            url: top.url)
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let repos = parseRepoList(context.settings["repo"] ?? "")
        let scope: String
        switch repos.count {
        case 0:  scope = "all repos"
        case 1:  scope = repos[0]
        default: scope = "\(repos.count) repos"
        }
        // Switch on the ENUM (not the raw string) so a new queue can't silently
        // fall through to the wrong label — the compiler makes this exhaustive.
        let queue = PRQueue(rawValue: context.settings["queue"] ?? "") ?? .reviewing
        let which: String
        switch queue {
        case .reviewing:       which = "my reviews"
        case .reviewRequested: which = "awaiting my review"
        case .reviewedBy:      which = "reviewed by me"
        case .authored:        which = "opened by me"
        }
        return "\(scope) · \(which)"
    }

    /// Fetch one poll's observation for `queue`. For `.reviewing` this is the UNION
    /// of review-requested + reviewed-by (GitHub has no single qualifier for "I'm a
    /// reviewer"), fetched as two concurrent queries and merged; every other queue
    /// is a single query.
    static func observe(_ queue: PRQueue, client: GitHubAPIClient,
                        repos: [String], limit: Int, now: Date) async throws -> PRListObservation {
        guard queue == .reviewing else {
            return try await client.pullRequestList(queue: queue, repos: repos, limit: limit, now: now)
        }
        async let requested = client.pullRequestList(queue: .reviewRequested, repos: repos, limit: limit, now: now)
        async let reviewed  = client.pullRequestList(queue: .reviewedBy, repos: repos, limit: limit, now: now)
        // All-or-nothing on purpose: if either side fails we throw, and the caller's
        // stale-snapshot fallback keeps the last good list on screen rather than
        // showing half a union that looks like PRs vanished. A transient blip just
        // delays freshness, it doesn't blank or truncate the panel.
        let (a, b) = try await (requested, reviewed)
        let merged = mergeReviewing(a.items, b.items)
        // Count from the servers' REAL totals (each `total` is GitHub's issueCount,
        // not the page cap), so the pill can't silently undercount a prolific
        // reviewer — the exact case this queue exists for. Show at most `limit`.
        return PRListObservation(total: reviewingTotal(a, b),
                                 items: Array(merged.prefix(limit)), observedAt: now)
    }

    /// The honest union count: both sides' true totals minus the overlap we can see
    /// (a PR re-requested after review is in both). Uses server `total`s so it never
    /// undercounts when either side has more PRs than one page holds; the only
    /// imprecision is a rare re-request duplicate sitting beyond the fetched page,
    /// which would nudge the count UP by one — never hide a PR.
    static func reviewingTotal(_ a: PRListObservation, _ b: PRListObservation) -> Int {
        func keys(_ prs: [PRSummary]) -> Set<String> { Set(prs.map { "\($0.repo)#\($0.number)" }) }
        let overlap = keys(a.items).intersection(keys(b.items)).count
        return max(a.total + b.total - overlap, 0)
    }

    /// Merge the two reviewer queues into one list: de-duplicate by repo#number (a
    /// PR can be in BOTH after a re-request) and order newest-first so the list is
    /// stable across polls.
    static func mergeReviewing(_ requested: [PRSummary], _ reviewed: [PRSummary]) -> [PRSummary] {
        var seen = Set<String>()
        var merged: [PRSummary] = []
        for pr in requested + reviewed where seen.insert("\(pr.repo)#\(pr.number)").inserted { merged.append(pr) }
        return merged.sorted { $0.number > $1.number }
    }

    public func detail(for value: PRState) -> [DetailRow] {
        if value.items.isEmpty {
            // Only the genuine can't-read-this-repo case (a 4xx on a private repo
            // Perch isn't installed on) gets the "grant access" nudge — NOT a query
            // that succeeded and simply found nothing.
            if value.noAccess, let scope = value.repoScope {
                return [DetailRow(
                    id: "pr-none",
                    title: "No access to \(scope)",
                    subtitle: "Tap to grant Perch access on GitHub — or sign in with a token in Settings.",
                    tint: .warning, symbolName: "lock.circle",
                    url: "https://github.com/settings/installations")]
            }
            if value.count == 0 {
                // A clean empty: name the actual reason for THIS queue, so the user
                // knows it worked and can pick a different queue if they meant one.
                let whereIn = value.repoScope.map { " in \($0)" } ?? ""
                let msg: String
                switch value.queue {
                case .reviewing:       msg = "No PRs to review\(whereIn)"
                case .reviewRequested: msg = "No PRs awaiting your review\(whereIn)"
                case .reviewedBy:      msg = "You haven't reviewed any open PRs\(whereIn)"
                case .authored:        msg = "No open PRs you've opened\(whereIn)"
                }
                let hint = value.queue == .reviewRequested
                    ? "Looking for PRs you already reviewed? Switch \u{201C}Show\u{201D} to \u{201C}PRs I\u{2019}m reviewing\u{201D} in Settings."
                    : ""
                return [DetailRow(id: "pr-none", title: msg, subtitle: hint,
                                  tint: .neutral, symbolName: "checkmark.seal")]
            }
            return [DetailRow(id: "pr-empty", title: "\(value.count) waiting", tint: .warning)]
        }
        return value.items.map { pr in
            let review = Self.status(for: pr)
            let ci = value.showChecks ? Self.ciStatus(pr.checksState, done: pr.checksDone, total: pr.checksTotal) : nil
            // Subtitle names the source, whichever of CI / review the user chose to
            // show, and a comment count — so active discussion stays visible even
            // when a review DECISION word (e.g. "awaiting re-review") would
            // otherwise hide it. The note is skipped when the review label already
            // conveys comments (the "commented" / "N comments" fallback).
            let note = value.showReview ? Self.commentNote(for: pr, reviewLabel: review.label) : nil
            let parts = [pr.repo, ci?.label, value.showReview ? review.label : nil, note].compactMap { $0 }
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

    /// "N comment(s)" — the one place this string is built, so the row note and
    /// the review-label fallback can't drift apart.
    static func pluralComment(_ n: Int) -> String { "\(n) comment\(n == 1 ? "" : "s")" }

    /// A comment-count note for the panel row, so conversation stays visible next
    /// to the review-gate label. nil when there are none, or when the review label
    /// is ALREADY the exact same count (the "N comments" fallback) — but a bare
    /// "commented" (a COMMENT-type review, no count) still gets the note, since
    /// that's a different signal from the conversation-comment total.
    static func commentNote(for pr: PRSummary, reviewLabel: String) -> String? {
        guard pr.commentCount > 0, reviewLabel != pluralComment(pr.commentCount) else { return nil }
        return pluralComment(pr.commentCount)
    }

    /// Map a PR's review + merge status to a label, tint, and icon.
    static func status(for pr: PRSummary) -> (label: String, tint: Tint, symbol: String) {
        if pr.isDraft { return ("draft", .neutral, "pencil.circle") }
        if pr.mergeable == "CONFLICTING" { return ("conflicts", .critical, "exclamationmark.triangle.fill") }
        // The good end-state: approved, green, no conflicts — good to land.
        if pr.isReadyToMerge { return ("ready to merge", .good, "checkmark.seal.fill") }
        switch pr.reviewDecision {
        case "APPROVED":          return ("approved", .good, "checkmark.circle.fill")
        case "CHANGES_REQUESTED":
            // GitHub holds this decision until a reviewer re-reviews, so make it
            // actionable: unresolved threads ⇒ your move (resolve them); none
            // left ⇒ you've addressed them and it's waiting on the reviewer.
            if pr.unresolvedThreads > 0 {
                return ("\(pr.unresolvedLabel) to resolve", .critical, "text.bubble.fill")
            }
            return ("awaiting re-review", .warning, "clock.arrow.circlepath")
        case "REVIEW_REQUIRED":   return ("review required", .warning, "clock.fill")
        default:
            // No formal decision, but say whether people have engaged instead of a
            // bare "open": a Comment review → "commented"; conversation → "N
            // comments". (A plain "Comment" review never sets reviewDecision, so
            // "open" alone hides that the PR has been looked at.)
            if pr.reviewCount > 0 { return ("commented", .info, "text.bubble.fill") }
            if pr.commentCount > 0 { return (pluralComment(pr.commentCount), .info, "bubble.left.fill") }
            return ("open", .info, "arrow.triangle.pull")
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
