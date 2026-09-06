import Foundation
import PerchCore
import PerchModuleKit
import PerchSync
import PerchGitHub

/// The full state of a watched build — the pill needs only `.state`, the panel
/// uses the rest (workflow, commit, duration, link).
public struct BuildInfo: Sendable, Equatable {
    public var state: BuildState
    public var workflowName: String
    public var branch: String
    public var shortSHA: String
    public var durationText: String
    public var url: String

    public static let unknown = BuildInfo(
        state: .unknown, workflowName: "", branch: "", shortSHA: "", durationText: "", url: "")
}

/// The real build signal: polls a repo's latest GitHub Actions run and drives
/// the notch pill, and contributes a detail row (workflow · commit · duration +
/// open-run link) to the panel. Routes every observation through `VersionedStore`
/// so it inherits the accuracy guarantees — ordering and honest freshness.
public struct GitHubBuildsModule: NotchModule {
    public typealias State = BuildInfo

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

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<BuildInfo>> {
        let clock = context.clock
        let client = client
        let (owner, repo, branch) = (owner, repo, branch)

        return AsyncStream { continuation in
            let store = VersionedStore<String, BuildInfo>(clock: clock)
            let key = "\(owner)/\(repo)@\(branch)"
            var lastLog: String?   // log only when the outcome changes
            var failures = 0       // for exponential backoff on the error path
            let backoff = Backoff(base: 10, cap: 300)
            var etag: String?      // conditional-request tag; 304s are free
            var lastState: BuildState = .unknown

            let task = Task {
                continuation.yield(Snapshot(value: .unknown, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    var nextDelay: Double = 60
                    do {
                        let fetch = try await client.latestBuild(owner: owner, repo: repo, branch: branch, etag: etag)
                        failures = 0
                        switch fetch {
                        case .notModified:
                            // Unchanged since last poll — free 304, nothing to do.
                            nextDelay = (lastState == .running) ? 15 : 60
                        case .ok(let observation?, let newEtag):
                            etag = newEtag
                            let info = BuildInfo(
                                state: Self.map(observation.state),
                                workflowName: observation.workflowName,
                                branch: observation.branch,
                                shortSHA: observation.shortSHA,
                                durationText: Self.formatDuration(observation.durationSeconds),
                                url: observation.url)
                            lastState = info.state
                            let line = "\(info.state)"
                            if lastLog != line { print("[perch] build poll \(key): \(line)"); lastLog = line }
                            let accepted = await store.apply(info, forKey: key, version: observation.updatedAt)
                            if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                                continuation.yield(snapshot)
                            }
                            nextDelay = (info.state == .running) ? 15 : 60
                        case .ok(nil, let newEtag):
                            etag = newEtag
                            if lastLog != "none" { print("[perch] build poll \(key): no runs found"); lastLog = "none" }
                        }
                    } catch {
                        failures += 1
                        let line = "error \(error)"
                        if lastLog != line { print("[perch] build poll \(key): \(line)"); lastLog = line }
                        if let stale = await store.snapshot(forKey: key, ttl: 0) {
                            continuation.yield(stale)
                        } else {
                            continuation.yield(Snapshot(value: .unknown, freshness: .error("\(error)"), asOf: clock.now()))
                        }
                        // Back off exponentially; auth failures wait the full cap
                        // (retrying won't help until the user reconnects).
                        nextDelay = Self.isAuthError(error) ? backoff.cap : backoff.delay(consecutiveFailures: failures)
                    }
                    try? await Task.sleep(for: .seconds(nextDelay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: BuildInfo, in slot: Slot) -> PillFace {
        buildFace(for: value.state, in: slot)
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        "\(owner)/\(repo) · \(branch)"
    }

    public func detail(for value: BuildInfo) -> [DetailRow] {
        guard value.state != .unknown, !value.url.isEmpty else { return [] }
        let bits = [value.branch, value.shortSHA, value.durationText].filter { !$0.isEmpty }
        return [DetailRow(
            id: "build",
            title: value.workflowName.isEmpty ? "Latest run" : value.workflowName,
            subtitle: bits.joined(separator: " · "),
            tint: buildFace(for: value.state, in: .panel).tint,
            symbolName: buildFace(for: value.state, in: .panel).symbolName,
            url: value.url)]
    }

    public func notification(for value: BuildInfo, previous: BuildInfo?) -> ModuleAlert? {
        // Alert when a build newly turns red — once per failing commit.
        guard value.state == .failing, previous?.state != .failing else { return nil }
        let branch = value.branch.isEmpty ? "" : " · \(value.branch)"
        return ModuleAlert(
            id: "build-failing-\(value.shortSHA.isEmpty ? value.url : value.shortSHA)",
            title: "Build failing",
            body: "\(value.workflowName.isEmpty ? "CI" : value.workflowName)\(branch)")
    }

    /// A 401 (revoked/expired token) won't fix itself by retrying — back off hard.
    static func isAuthError(_ error: Error) -> Bool {
        if case GitHubAuthError.http(let status) = error, status == 401 { return true }
        if case GitHubAuthError.notConnected = error { return true }
        return false
    }

    private static func map(_ state: RunState) -> BuildState {
        switch state {
        case .running:            return .running
        case .passing:            return .passing
        case .failing:            return .failing
        case .neutral, .unknown:  return .unknown
        }
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "" }
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(String(format: "%02ds", seconds % 60))"
    }
}
