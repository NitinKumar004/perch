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

    public init(count: Int, items: [PRSummary], repoScope: String? = nil) {
        self.count = count
        self.items = items
        self.repoScope = repoScope
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

        return AsyncStream { continuation in
            let store = VersionedStore<String, PRState>(clock: clock)
            let key = "\(queue.rawValue)#\(repo ?? "*")"
            var lastError: String?   // so a repeating error is logged once, not every poll

            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = 90
                    do {
                        let observation = try await client.pullRequestList(queue: queue, repo: repo, now: clock.now())
                        if lastError != nil { print("[perch] pr poll \(key): recovered"); lastError = nil }
                        let state = PRState(count: observation.total, items: observation.items, repoScope: repo)
                        let accepted = await store.apply(state, forKey: key, version: observation.observedAt)
                        if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                            continuation.yield(snapshot)
                        }
                    } catch {
                        let desc = "\(error)"
                        if lastError != desc { print("[perch] pr poll \(key): error \(desc)"); lastError = desc }
                        // A 4xx on a repo-scoped query means the current credential
                        // can't see that repo — a private repo the GitHub App isn't
                        // installed on (GitHub returns 422 for that). Show the honest
                        // "needs access" hint instead of an error loop.
                        if case GitHubAuthError.http(let status) = error,
                           (400..<500).contains(status), let repo {
                            let noAccess = PRState(count: 0, items: [], repoScope: repo)
                            continuation.yield(Snapshot(value: noAccess, freshness: .unknown, asOf: clock.now()))
                        } else if let stale = await store.snapshot(forKey: key, ttl: 0) {
                            continuation.yield(stale)
                        } else {
                            continuation.yield(Snapshot(value: .empty, freshness: .error("\(error)"), asOf: clock.now()))
                        }
                        nextDelay = 15
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
                ?? "\(value.count) PR\(value.count == 1 ? "" : "s") waiting on you")
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
                    subtitle: "If it's private, Perch needs access — sign in with a token or install the app on that repo.",
                    tint: .neutral, symbolName: "questionmark.circle")]
            }
            return value.count == 0 ? [] : [DetailRow(id: "pr-empty", title: "\(value.count) waiting", tint: .warning)]
        }
        return value.items.map { pr in
            DetailRow(
                id: "pr-\(pr.repo)-\(pr.number)",
                title: "#\(pr.number) \(pr.title)",
                subtitle: pr.repo,
                tint: .info,
                symbolName: "arrow.triangle.pull",
                url: pr.url)
        }
    }
}
