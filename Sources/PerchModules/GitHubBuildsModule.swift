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
    /// The run number ("#1636") so the panel names the exact run, not just "CI".
    public var runNumber: Int
    /// The run's display title (e.g. "v2.11.0") — the human "what build ran".
    public var displayTitle: String
    public var branch: String
    public var shortSHA: String
    public var durationText: String
    public var url: String
    /// Seconds the current run has been going (only meaningful while `.running`),
    /// used with `predictedSeconds` to drive the live progress bar + ETA.
    public var elapsedSeconds: Int
    /// Learned total duration for this workflow (median of past runs), or nil when
    /// there's no history yet or the ETA is turned off. nil → elapsed-only, no bar.
    public var predictedSeconds: Int?

    public init(state: BuildState, workflowName: String, branch: String,
                shortSHA: String, durationText: String, url: String,
                runNumber: Int = 0, displayTitle: String = "",
                elapsedSeconds: Int = 0, predictedSeconds: Int? = nil) {
        self.state = state
        self.workflowName = workflowName
        self.runNumber = runNumber
        self.displayTitle = displayTitle
        self.branch = branch
        self.shortSHA = shortSHA
        self.durationText = durationText
        self.url = url
        self.elapsedSeconds = elapsedSeconds
        self.predictedSeconds = predictedSeconds
    }

    /// "CI #1636" — the exact run identity. Falls back to just the workflow name
    /// (or "Latest run") when the number is unknown.
    public var runLabel: String {
        let name = workflowName.isEmpty ? "Latest run" : workflowName
        return runNumber > 0 ? "\(name) #\(runNumber)" : name
    }

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
    /// Pin to one workflow by name (e.g. "CI") so the pill doesn't flip between a
    /// repo's several workflows; blank = the latest run of any workflow.
    private let workflow: String
    /// Where completed-run durations are learned from, so a running build shows a
    /// real "≈4m left" instead of a static spinner. Shared across build modules.
    private let history: RunHistoryStore

    public init(client: GitHubAPIClient, owner: String, repo: String, branch: String = "main",
                workflow: String = "", history: RunHistoryStore = RunHistoryStore()) {
        self.client = client
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.workflow = workflow
        self.history = history
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<BuildInfo>> {
        let clock = context.clock
        let client = client
        let (owner, repo, branch, workflow) = (owner, repo, branch, workflow)
        let history = history
        let idleInterval = context.refreshSeconds(fallback: 60, minimum: 15)
        // Build-activity controls — every one user-tunable, sensible defaults:
        let showActivity = context.bool("activity", fallback: true)      // live bar while running
        let showETA = showActivity && context.setting("eta", fallback: "learned") == "learned"
        let etaWindow = context.int("etaWindow", fallback: 10, minimum: 2, maximum: 100)

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
                    var nextDelay: Double = idleInterval
                    // Respect the shared rate-limit budget so several GitHub pollers
                    // running together back off in concert before hitting a 403.
                    let throttle = await client.rateLimit.throttleDelay()
                    if throttle > 0 { try? await Task.sleep(for: .seconds(min(throttle, 60))) }
                    do {
                        let fetch = try await client.latestBuild(owner: owner, repo: repo, branch: branch, workflow: workflow, etag: etag)
                        failures = 0
                        switch fetch {
                        case .notModified:
                            // Unchanged since last poll — free 304, nothing to do.
                            nextDelay = (lastState == .running) ? 15 : idleInterval
                        case .pinnedAbsent(let newEtag):
                            // Pinned workflow wasn't in the fetched window (other
                            // workflows ran more recently). KEEP the last-known build
                            // — don't wipe to "unknown" the way a genuine no-runs does.
                            etag = newEtag
                            if lastLog != "pinned-absent" { print("[perch] build poll \(key): pinned workflow not in window"); lastLog = "pinned-absent" }
                            nextDelay = idleInterval
                        case .ok(let observation?, let newEtag):
                            etag = newEtag
                            let mapped = BuildState(observation.state)
                            // History is per workflow (a repo can run several), so a
                            // slow deploy job's ETA never bleeds into a fast test job.
                            let historyKey = "\(key)#\(observation.workflowName)"
                            // Learn: when a run reaches a terminal state, record its
                            // total duration. The store dedups per run url, so this
                            // stays correct across polls AND across a module rebuild
                            // (settings change / restart) where the loop's own memory
                            // would have re-counted the same finished run.
                            if showActivity, mapped == .passing || mapped == .failing {
                                await history.recordIfNewRun(observation.durationSeconds,
                                                             forKey: historyKey, runURL: observation.url,
                                                             runUpdatedAt: observation.updatedAt,
                                                             window: etaWindow)
                            }
                            // Predict: while running, offer the learned ETA (median of
                            // past runs) so the pill shows "≈4m left", not a bare dot.
                            var predicted: Int?
                            if showETA, mapped == .running {
                                predicted = RunHistory.predict(durations: await history.durations(forKey: historyKey))
                            }
                            let info = BuildInfo(
                                state: mapped,
                                workflowName: observation.workflowName,
                                branch: observation.branch,
                                shortSHA: observation.shortSHA,
                                durationText: Self.formatDuration(observation.durationSeconds),
                                url: observation.url,
                                runNumber: observation.runNumber,
                                displayTitle: observation.displayTitle,
                                // Only carry elapsed when activity is ON — so the
                                // face/detail special-casing (keyed on elapsed > 0)
                                // fully reverts to the pre-feature text when the user
                                // turns the toggle off, not just the number.
                                elapsedSeconds: (showActivity && mapped == .running) ? observation.durationSeconds : 0,
                                predictedSeconds: predicted)
                            lastState = info.state
                            let line = "\(info.state)"
                            if lastLog != line { print("[perch] build poll \(key): \(line)"); lastLog = line }
                            let accepted = await store.apply(info, forKey: key, version: observation.updatedAt)
                            if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                                continuation.yield(snapshot)
                            }
                            nextDelay = (info.state == .running) ? 15 : idleInterval
                        case .ok(nil, let newEtag):
                            etag = newEtag
                            if lastLog != "none" { print("[perch] build poll \(key): no runs found"); lastLog = "none" }
                            // No runs (e.g. the last one aged out of Actions' 90-day
                            // retention) — surface a fresh "unknown" so the pill
                            // doesn't freeze on a stale "passing/failing" forever,
                            // and honour the configured idle interval like every
                            // other branch (was silently stuck at the 60s default).
                            // Forget the stored build too, so a LATER transient
                            // fetch error's catch-path can't resurrect the old
                            // "passing/failing" as stale.
                            await store.remove(forKey: key)
                            lastState = .unknown
                            continuation.yield(Snapshot(value: .unknown, freshness: .live, asOf: clock.now()))
                            nextDelay = idleInterval
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
        let base = buildFace(for: value.state, in: slot)
        // While a build is running, turn the static spinner into a live gauge: a
        // progress bar filled to elapsed÷learned-ETA, with the countdown in the
        // tooltip. No history yet → no bar (progress nil), tooltip shows elapsed.
        guard value.state == .running, value.elapsedSeconds > 0 else { return base }
        let eta = RunHistory.etaText(elapsedSeconds: value.elapsedSeconds,
                                     predictedSeconds: value.predictedSeconds)
        return PillFace(text: base.text, symbolName: base.symbolName, tint: base.tint,
                        tooltip: "Build running · \(eta)", segments: base.segments,
                        badge: base.badge,
                        progress: RunHistory.progress(elapsedSeconds: value.elapsedSeconds,
                                                      predictedSeconds: value.predictedSeconds))
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let branchLabel = (branch.isEmpty || branch == "*") ? "any branch" : branch
        let pinned = workflow.trimmingCharacters(in: .whitespaces)
        let scope = pinned.isEmpty ? branchLabel : "\(pinned) · \(branchLabel)"
        return "\(owner)/\(repo) · \(scope)"
    }

    public func detail(for value: BuildInfo) -> [DetailRow] {
        guard value.state != .unknown, !value.url.isEmpty else { return [] }
        // Subtitle leads with the run's display title (the "what build ran", e.g.
        // "v2.11.0"), then branch · commit · duration. While running, the live
        // countdown ("≈4m left") replaces the duration.
        var bits = [value.displayTitle, value.branch, value.shortSHA, value.durationText]
        if value.state == .running, value.elapsedSeconds > 0 {
            bits = [value.displayTitle,
                    RunHistory.etaText(elapsedSeconds: value.elapsedSeconds,
                                       predictedSeconds: value.predictedSeconds),
                    value.branch, value.shortSHA]
        }
        bits = bits.filter { !$0.isEmpty }
        // Key the row id off the repo path (the run id in the url changes every
        // build) so two Builds sections watching different repos don't collide on
        // a shared "build" id — a bare literal made a per-row action (copy-link)
        // fire on both. Stable per repo, unique across sections.
        let repoKey = value.url.components(separatedBy: "/actions").first ?? value.url
        return [DetailRow(
            id: "build-\(repoKey)",
            title: value.runLabel,   // "CI #1636" — the exact run
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
            body: "\(value.workflowName.isEmpty ? "CI" : value.workflowName)\(branch)",
            url: value.url.isEmpty ? nil : value.url)
    }

    /// A 401 (revoked/expired token) won't fix itself by retrying — back off hard.
    static func isAuthError(_ error: Error) -> Bool {
        if case GitHubAuthError.http(let status) = error, status == 401 { return true }
        if case GitHubAuthError.notConnected = error { return true }
        return false
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "" }
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m\(String(format: "%02ds", seconds % 60))"
    }
}
