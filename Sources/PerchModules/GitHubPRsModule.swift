import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// PR-queue state: the count drives the pill, the list drives the panel.
public struct PRState: Sendable, Equatable {
    public var count: Int
    public var items: [PRSummary]

    public static let empty = PRState(count: 0, items: [])
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

            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = 90
                    do {
                        let observation = try await client.pullRequestList(queue: queue, repo: repo, now: clock.now())
                        print("[perch] pr poll \(key): \(observation.total)")
                        let state = PRState(count: observation.total, items: observation.items)
                        let accepted = await store.apply(state, forKey: key, version: observation.observedAt)
                        if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                            continuation.yield(snapshot)
                        }
                    } catch {
                        print("[perch] pr poll \(key): error \(error)")
                        if let stale = await store.snapshot(forKey: key, ttl: 0) {
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

    public func detail(for value: PRState) -> [DetailRow] {
        if value.items.isEmpty {
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
