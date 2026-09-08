import Foundation
import PerchCore

/// Local, persisted record of how long past CI runs took, per repo·workflow, so
/// the build activity can learn an ETA. It's an `actor`, so concurrent build
/// pollers read/write safely; the durations live in a small JSON file next to the
/// config (`~/.config/perch/run-history.json`) and **never leave the Mac**.
///
/// The prediction math is the pure `RunHistory`; this only owns storage, the
/// capped rolling window per key, and the "record each finished run exactly once"
/// guard — which lives HERE (not in the poll loop) so it survives a module
/// rebuild: the app tears down and recreates the build module on every settings
/// change, and an in-memory guard would let the same finished run be re-recorded
/// after each rebuild, quietly skewing the learned median.
public actor RunHistoryStore {
    /// The on-disk shape: durations per key, plus the last run URL recorded per
    /// key so a finished run is never double-counted across app restarts.
    private struct Persisted: Codable {
        var durations: [String: [Int]]
        var lastRun: [String: String]
    }

    private let fileURL: URL
    private var durationsByKey: [String: [Int]]
    private var lastRunByKey: [String: String]
    private var loaded = false

    /// The canonical history location, beside the layout config.
    public static var defaultFileURL: URL { PerchPaths.configFile("run-history.json") }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? RunHistoryStore.defaultFileURL
        self.durationsByKey = [:]
        self.lastRunByKey = [:]
    }

    /// The stored completed-run durations (seconds) for a key, oldest → newest.
    public func durations(forKey key: String) -> [Int] {
        loadIfNeeded()
        return durationsByKey[key] ?? []
    }

    /// Record a finished run's total duration for a key — but only if THIS
    /// completion hasn't already been recorded, so a restart or settings-change
    /// that rebuilds the poller can't re-count the same run. Identity is
    /// `runURL` + `runUpdatedAt`, NOT the url alone: GitHub's "re-run" reuses the
    /// same run url but resets the timing and advances `updated_at`, so that's a
    /// genuinely new completion whose (longer/shorter) duration must be learned —
    /// keying on url only would silently drop it. Keeps only the last `window`
    /// durations. Ignores non-positive durations / blank urls. Returns true when
    /// it actually recorded. Persists immediately.
    @discardableResult
    public func recordIfNewRun(_ seconds: Int, forKey key: String, runURL: String,
                               runUpdatedAt: Date, window: Int) -> Bool {
        guard seconds > 0, window > 0, !runURL.isEmpty else { return false }
        loadIfNeeded()
        let identity = "\(runURL)#\(Int(runUpdatedAt.timeIntervalSince1970))"
        guard lastRunByKey[key] != identity else { return false }   // already counted this completion
        lastRunByKey[key] = identity
        append(seconds, forKey: key, window: window)
        persist()
        return true
    }

    /// Append a duration under the rolling window, without the per-run dedup — the
    /// storage primitive. `recordIfNewRun` is the guarded entry point the poller
    /// uses; this stays available for callers that own their own dedup.
    public func record(_ seconds: Int, forKey key: String, window: Int) {
        guard seconds > 0, window > 0 else { return }
        loadIfNeeded()
        append(seconds, forKey: key, window: window)
        persist()
    }

    private func append(_ seconds: Int, forKey key: String, window: Int) {
        var list = durationsByKey[key] ?? []
        list.append(seconds)
        if list.count > window { list.removeFirst(list.count - window) }
        durationsByKey[key] = list
    }

    // MARK: - Persistence (best-effort, never throws into the poll loop)

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            durationsByKey = decoded.durations
            lastRunByKey = decoded.lastRun
            return
        }
        // Back-compat: an older file was a bare [key: [durations]] with no lastRun.
        if let legacy = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            durationsByKey = legacy
            return
        }
        // Unreadable/corrupt: preserve it for inspection before starting fresh, so
        // the next persist() doesn't silently clobber it — mirrors ConfigStore.
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("run-history.corrupt.\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private func persist() {
        let snapshot = Persisted(durations: durationsByKey, lastRun: lastRunByKey)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
