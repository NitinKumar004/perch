import Testing
import Foundation
@testable import PerchModules

// The build-activity ETA is only ever as trustworthy as this pure math and the
// little persisted store behind it, so both are pinned here: the median must
// shrug off an outlier, progress must clamp, the countdown must read right in
// every phase, and the store must keep a rolling window and survive a reload.

@Suite struct RunHistoryMathTests {
    @Test func medianHandlesEmptyOddEven() {
        #expect(RunHistory.median([]) == nil)
        #expect(RunHistory.median([7]) == 7)
        #expect(RunHistory.median([1, 100, 3]) == 3)      // sorted middle, not mean
        #expect(RunHistory.median([2, 4, 6, 8]) == 5)     // mean of two middles
    }

    @Test func predictIgnoresNonPositiveAndEmpty() {
        #expect(RunHistory.predict(durations: []) == nil)
        #expect(RunHistory.predict(durations: [0, -5]) == nil)
        // One slow run (600) can't drag the estimate off the cluster.
        #expect(RunHistory.predict(durations: [100, 110, 120, 105, 600]) == 110)
    }

    @Test func progressClampsAndNilsWithoutPrediction() {
        #expect(RunHistory.progress(elapsedSeconds: 30, predictedSeconds: nil) == nil)
        #expect(RunHistory.progress(elapsedSeconds: 30, predictedSeconds: 0) == nil)
        #expect(RunHistory.progress(elapsedSeconds: 60, predictedSeconds: 120) == 0.5)
        #expect(RunHistory.progress(elapsedSeconds: 999, predictedSeconds: 120) == 1) // capped
    }

    @Test func etaTextReadsRightInEveryPhase() {
        // No prediction → elapsed only, never invents a number.
        #expect(RunHistory.etaText(elapsedSeconds: 200, predictedSeconds: nil) == "running 3m")
        // Turned off → elapsed only even with a prediction.
        #expect(RunHistory.etaText(elapsedSeconds: 40, predictedSeconds: 240, showETA: false) == "running 40s")
        // On track → remaining.
        #expect(RunHistory.etaText(elapsedSeconds: 60, predictedSeconds: 300) == "≈4m left")
        // Past the estimate → overdue.
        #expect(RunHistory.etaText(elapsedSeconds: 400, predictedSeconds: 280) == "overdue +2m")
    }
}

@Suite struct RunHistoryStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-runhistory-\(UUID().uuidString).json")
    }

    @Test func recordsKeepsRollingWindowAndIgnoresBadValues() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RunHistoryStore(fileURL: url)

        await store.record(-1, forKey: "k", window: 3)   // ignored
        await store.record(0, forKey: "k", window: 3)     // ignored
        #expect(await store.durations(forKey: "k") == [])

        for s in [100, 200, 300, 400] { await store.record(s, forKey: "k", window: 3) }
        // Only the last `window` survive, oldest dropped.
        #expect(await store.durations(forKey: "k") == [200, 300, 400])
        // Unknown key is empty, not a crash.
        #expect(await store.durations(forKey: "other") == [])
    }

    @Test func recordIfNewRunCountsEachRunOnceEvenAcrossReload() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RunHistoryStore(fileURL: url)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)

        // Same run url + same updated time, polled repeatedly → recorded once.
        #expect(await store.recordIfNewRun(120, forKey: "k", runURL: "run/1", runUpdatedAt: t0, window: 10) == true)
        #expect(await store.recordIfNewRun(120, forKey: "k", runURL: "run/1", runUpdatedAt: t0, window: 10) == false)
        #expect(await store.durations(forKey: "k") == [120])
        // A genuinely new run → counted.
        #expect(await store.recordIfNewRun(140, forKey: "k", runURL: "run/2", runUpdatedAt: t0, window: 10) == true)
        #expect(await store.durations(forKey: "k") == [120, 140])
        // A GitHub "re-run": SAME url as run/2 but a later updated time → a new
        // completion, so its (different) duration is learned, not dropped.
        #expect(await store.recordIfNewRun(90, forKey: "k", runURL: "run/2", runUpdatedAt: t1, window: 10) == true)
        #expect(await store.durations(forKey: "k") == [120, 140, 90])
        // Bad inputs are refused.
        #expect(await store.recordIfNewRun(0, forKey: "k", runURL: "run/3", runUpdatedAt: t0, window: 10) == false)
        #expect(await store.recordIfNewRun(50, forKey: "k", runURL: "", runUpdatedAt: t0, window: 10) == false)

        // The dedup marker persists: a fresh store (a module rebuild / relaunch)
        // still won't re-count run/2's re-run (same url + same updated time).
        let reloaded = RunHistoryStore(fileURL: url)
        #expect(await reloaded.recordIfNewRun(90, forKey: "k", runURL: "run/2", runUpdatedAt: t1, window: 10) == false)
        #expect(await reloaded.durations(forKey: "k") == [120, 140, 90])
    }

    @Test func persistsAcrossReload() async {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = RunHistoryStore(fileURL: url)
        await first.record(120, forKey: "repo#CI", window: 10)
        await first.record(140, forKey: "repo#CI", window: 10)

        // A fresh instance reads the same file back — the ETA survives relaunch.
        let reloaded = RunHistoryStore(fileURL: url)
        #expect(await reloaded.durations(forKey: "repo#CI") == [120, 140])
        #expect(RunHistory.predict(durations: await reloaded.durations(forKey: "repo#CI")) == 130)
    }
}
