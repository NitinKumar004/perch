import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// Shows your pull-request review queue on the notch — by default the count of
/// PRs waiting on *your* review (the "2 waiting on you" signal). Configurable
/// via settings: `queue` (review-requested | author) and an optional `repo`
/// scope.
///
/// Same `NotchModule` contract as every other module, so it is automatically
/// configurable and placeable once the config engine knows its id.
public struct GitHubPRsModule: NotchModule {
    public typealias State = Int   // the count

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

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Int>> {
        let clock = context.clock
        let client = client
        let queue = PRQueue(rawValue: context.settings["queue"] ?? "") ?? .reviewRequested
        let repo = context.settings["repo"]   // nil = across all accessible repos

        return AsyncStream { continuation in
            let store = VersionedStore<String, Int>(clock: clock)
            let key = "\(queue.rawValue)#\(repo ?? "*")"

            let task = Task {
                continuation.yield(Snapshot(value: 0, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = 90
                    do {
                        let observation = try await client.pullRequestCount(
                            queue: queue, repo: repo, now: clock.now())
                        print("[perch] pr poll \(key): \(observation.count)")
                        let accepted = await store.apply(
                            observation.count, forKey: key, version: observation.observedAt)
                        if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                            continuation.yield(snapshot)
                        }
                    } catch {
                        print("[perch] pr poll \(key): error \(error)")
                        if let stale = await store.snapshot(forKey: key, ttl: 0) {
                            continuation.yield(stale)
                        } else {
                            continuation.yield(Snapshot(value: 0, freshness: .error("\(error)"), asOf: clock.now()))
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

    public func face(for value: Int, in slot: Slot) -> PillFace {
        if value == 0 {
            return PillFace(text: "PR", symbolName: "checkmark.seal", tint: .neutral,
                            tooltip: "No PRs waiting on you")
        }
        return PillFace(text: "\(value)", symbolName: "arrow.triangle.pull",
                        tint: .warning, tooltip: "\(value) PR\(value == 1 ? "" : "s") waiting on your review")
    }
}
