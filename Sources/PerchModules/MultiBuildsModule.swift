import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// One repo's latest-build summary within the multi-repo view.
public struct RepoBuild: Sendable, Equatable {
    public var repo: String        // "owner/name"
    public var state: BuildState
    public var url: String
    public init(repo: String, state: BuildState, url: String) {
        self.repo = repo
        self.state = state
        self.url = url
    }
}

/// The whole board: one entry per watched repo.
public struct MultiBuildState: Sendable, Equatable {
    public var repos: [RepoBuild]
    public static let empty = MultiBuildState(repos: [])
    public init(repos: [RepoBuild]) { self.repos = repos }

    /// The worst state across all repos — drives the single pill.
    public var worst: BuildState {
        if repos.contains(where: { $0.state == .failing }) { return .failing }
        if repos.contains(where: { $0.state == .running }) { return .running }
        if repos.contains(where: { $0.state == .passing }) { return .passing }
        return .unknown
    }
    public var failingCount: Int { repos.filter { $0.state == .failing }.count }
}

/// Watch several repos' default-branch builds at once. The pill shows the worst
/// state across all of them (one red anywhere → red); the panel lists each repo
/// with its own status and open-run link. Configure with a comma-separated
/// `repos` setting ("owner/a, owner/b"); optional per-repo `branch` default.
public struct MultiBuildsModule: NotchModule {
    public typealias State = MultiBuildState

    public static let descriptor = ModuleDescriptor(
        id: "github.builds.multi",
        name: "Builds",
        summary: "Latest build across several repos at once.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: true
    )

    private let client: GitHubAPIClient

    public init(client: GitHubAPIClient) {
        self.client = client
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<MultiBuildState>> {
        let clock = context.clock
        let client = client
        let branch = context.settings["branch"] ?? "main"
        let repos = Self.parseRepos(context.settings["repos"] ?? "")
        let idleInterval = context.refreshSeconds(fallback: 90, minimum: 30)

        return AsyncStream { continuation in
            let store = VersionedStore<String, MultiBuildState>(clock: clock)
            let key = repos.joined(separator: ",")
            var failures = 0
            let backoff = Backoff(base: 15, cap: 300)

            let task = Task {
                continuation.yield(Snapshot(value: .empty, freshness: .unknown, asOf: clock.now()))
                if repos.isEmpty {
                    continuation.yield(Snapshot(value: .empty, freshness: .error("no repos configured"), asOf: clock.now()))
                    return
                }
                while !Task.isCancelled {
                    var nextDelay: Double = idleInterval
                    var results: [RepoBuild] = []
                    var anyError = false
                    for repo in repos {
                        // Back off with the shared budget so a wide fan-out never
                        // burns the token's REST limit mid-sweep.
                        let throttle = await client.rateLimit.throttleDelay()
                        if throttle > 0 { try? await Task.sleep(for: .seconds(min(throttle, 60))) }
                        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
                        guard parts.count == 2 else { continue }
                        do {
                            let fetch = try await client.latestBuild(owner: parts[0], repo: parts[1], branch: branch, etag: nil)
                            if case .ok(let observation?, _) = fetch {
                                results.append(RepoBuild(repo: repo, state: Self.map(observation.state), url: observation.url))
                            } else {
                                results.append(RepoBuild(repo: repo, state: .unknown,
                                                         url: "https://github.com/\(repo)/actions"))
                            }
                        } catch {
                            anyError = true
                            results.append(RepoBuild(repo: repo, state: .unknown,
                                                     url: "https://github.com/\(repo)/actions"))
                        }
                    }

                    if anyError {
                        failures += 1
                        nextDelay = backoff.delay(consecutiveFailures: failures)
                    } else {
                        failures = 0
                    }
                    let state = MultiBuildState(repos: results)
                    let accepted = await store.apply(state, forKey: key, version: clock.now())
                    if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                        continuation.yield(snapshot)
                    }
                    // Poll faster while anything is still running.
                    if !anyError && state.worst == .running { nextDelay = min(nextDelay, 20) }
                    try? await Task.sleep(for: .seconds(nextDelay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: MultiBuildState, in slot: Slot) -> PillFace {
        let base = buildFace(for: value.worst, in: slot)
        // Show how many are red so the count is glanceable, not just the colour.
        let text = value.failingCount > 0 ? "\(value.failingCount)✗" : base.text
        return PillFace(text: text, symbolName: base.symbolName, tint: base.tint,
                        tooltip: "\(value.repos.count) repos · \(value.failingCount) failing")
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let repos = Self.parseRepos(context.settings["repos"] ?? "")
        return repos.isEmpty ? "no repos set" : "\(repos.count) repos"
    }

    public func detail(for value: MultiBuildState) -> [DetailRow] {
        value.repos.map { rb in
            let face = buildFace(for: rb.state, in: .panel)
            return DetailRow(
                id: "multibuild-\(rb.repo)",
                title: rb.repo,
                subtitle: Self.stateLabel(rb.state),
                tint: face.tint,
                symbolName: face.symbolName,
                url: rb.url)
        }
    }

    public func notification(for value: MultiBuildState, previous: MultiBuildState?) -> ModuleAlert? {
        guard let previous else { return nil }
        // Alert for any repo that newly turned red.
        let wasFailing = Set(previous.repos.filter { $0.state == .failing }.map(\.repo))
        let nowFailing = value.repos.filter { $0.state == .failing && !wasFailing.contains($0.repo) }
        guard let first = nowFailing.first else { return nil }
        return ModuleAlert(id: "multibuild-failing-\(first.repo)-\(first.url)",
                           title: "Build failing", body: first.repo, url: first.url)
    }

    static func parseRepos(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("/") && !$0.isEmpty }
    }

    static func stateLabel(_ state: BuildState) -> String {
        switch state {
        case .passing: return "passing"
        case .failing: return "failing"
        case .running: return "running"
        case .unknown: return "no data"
        }
    }

    private static func map(_ state: RunState) -> BuildState {
        switch state {
        case .running:           return .running
        case .passing:           return .passing
        case .failing:           return .failing
        case .neutral, .unknown: return .unknown
        }
    }
}
