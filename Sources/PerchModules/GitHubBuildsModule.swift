import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// The real build signal: polls a repo's latest GitHub Actions run and drives
/// the notch pill. It routes every observation through the `VersionedStore`, so
/// it inherits the exact accuracy guarantees the demo module was proving —
/// ordering, and honest freshness.
///
/// It implements the same `NotchModule` contract as `FakeBuildModule`; the app
/// swaps one for the other and nothing else changes.
public struct GitHubBuildsModule: NotchModule {
    public typealias State = BuildState

    public static let descriptor = ModuleDescriptor(
        id: "github.builds",
        name: "Build",
        summary: "Latest GitHub Actions run for a repo.",
        supportedSlots: [.leftPill, .panel],
        requiresConnection: true
    )

    private let client: GitHubAPIClient
    private let owner: String
    private let repo: String
    private let branch: String

    public init(client: GitHubAPIClient, owner: String, repo: String, branch: String = "main") {
        self.client = client
        self.owner = owner
        self.repo = repo
        self.branch = branch
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<BuildState>> {
        let clock = context.clock
        let client = client
        let (owner, repo, branch) = (owner, repo, branch)

        return AsyncStream { continuation in
            let store = VersionedStore<String, BuildState>(clock: clock)
            let key = "\(owner)/\(repo)@\(branch)"

            let task = Task {
                continuation.yield(Snapshot(value: .unknown, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = 60
                    do {
                        if let observation = try await client.latestBuild(owner: owner, repo: repo, branch: branch) {
                            print("[perch] build poll \(key): \(observation.state) @ \(observation.updatedAt)")
                            let state = Self.map(observation.state)
                            let accepted = await store.apply(state, forKey: key, version: observation.updatedAt)
                            if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                                continuation.yield(snapshot)
                            }
                            // Poll fast while something is in flight, slowly when idle.
                            nextDelay = (state == .running) ? 15 : 60
                        } else {
                            print("[perch] build poll \(key): no runs found")
                        }
                    } catch {
                        print("[perch] build poll \(key): error \(error)")
                        // Be honest: show the last value as stale, or unknown/error
                        // if we've never had one. Never a confident, wrong value.
                        if let stale = await store.snapshot(forKey: key, ttl: 0) {
                            continuation.yield(stale)
                        } else {
                            continuation.yield(Snapshot(value: .unknown, freshness: .error("\(error)"), asOf: clock.now()))
                        }
                        // Recover quickly after a transient failure or a just-completed
                        // GitHub connect, instead of waiting a full idle interval.
                        nextDelay = 8
                    }
                    try? await Task.sleep(for: .seconds(nextDelay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: BuildState, in slot: Slot) -> PillFace {
        buildFace(for: value, in: slot)
    }

    private static func map(_ state: RunState) -> BuildState {
        switch state {
        case .running:            return .running
        case .passing:            return .passing
        case .failing:            return .failing
        case .neutral, .unknown:  return .unknown
        }
    }
}
