import Testing
import Foundation
import PerchCore
@testable import PerchModuleKit

@Suite struct PollingStreamTests {
    /// A fixed clock so snapshot timestamps are deterministic.
    struct FixedClock: Clock {
        let date: Date
        func now() -> Date { date }
    }

    @Test func emitsSeedThenSamplesThenTerminatesOnCancel() async {
        let clock = FixedClock(date: Date(timeIntervalSince1970: 0))
        // Fast interval; the consumer cancels after a few emissions.
        let stream = AsyncStream.periodic(every: 0.01, clock: clock, seed: -1) { 42 }

        var seen: [Int] = []
        for await snap in stream {
            seen.append(snap.value)
            if seen.count >= 3 { break }   // breaking the loop tears the stream down
        }

        // Seed emitted first (as .unknown), then live samples.
        #expect(seen.first == -1)
        #expect(seen.dropFirst().allSatisfy { $0 == 42 })
        #expect(seen.count == 3)
    }

    @Test func seedIsUnknownAndSamplesAreLive() async {
        let clock = FixedClock(date: Date(timeIntervalSince1970: 0))
        let stream = AsyncStream.periodic(every: 0.01, clock: clock, seed: 0) { 1 }

        var freshnesses: [Freshness] = []
        for await snap in stream {
            freshnesses.append(snap.freshness)
            if freshnesses.count >= 2 { break }
        }
        #expect(freshnesses.first == .unknown)   // the seed placeholder
        #expect(freshnesses.last == .live)       // a real sample
    }

    @Test func nilSampleTicksAreSkipped() async {
        let clock = FixedClock(date: Date(timeIntervalSince1970: 0))
        // A counter that returns nil on the first sample tick, then a value —
        // the nil tick must not emit, so the first *sample* seen is the value.
        let box = Box()
        let stream = AsyncStream.periodic(every: 0.01, clock: clock, seed: -1) {
            await box.next()
        }
        var samples: [Int] = []
        for await snap in stream where snap.value != -1 {   // ignore the seed
            samples.append(snap.value)
            if samples.count >= 1 { break }
        }
        #expect(samples == [7])   // the nil tick produced no emission
    }

    @Test func failingReaderAfterLiveReEmitsLastValueAsStale() async {
        let t0 = Date(timeIntervalSince1970: 1000)
        let clock = FixedClock(date: t0)
        // One live value (7), then nil forever — the reader broke after a good read.
        let box = FailAfterFirst()
        let stream = AsyncStream.periodic(every: 0.01, clock: clock, seed: -1) { await box.next() }

        var snaps: [Snapshot<Int>] = []
        for await snap in stream where snap.value != -1 {   // ignore the seed
            snaps.append(snap)
            if snaps.count >= 3 { break }
        }
        // First real emission is live; the failed ticks re-emit the last value as
        // STALE (dated from when it was confirmed) — never a frozen "live" lie.
        #expect(snaps[0].freshness == .live)
        #expect(snaps[0].value == 7)
        #expect(snaps[1].freshness == .stale(since: t0))
        #expect(snaps[1].value == 7)   // last good value carried forward, but marked stale
        #expect(snaps[2].freshness == .stale(since: t0))
    }

    /// Returns nil once, then 7 forever.
    actor Box {
        private var calls = 0
        func next() -> Int? {
            calls += 1
            return calls == 1 ? nil : 7
        }
    }

    /// Returns 7 once, then nil forever (a reader that breaks after a good read).
    actor FailAfterFirst {
        private var calls = 0
        func next() -> Int? {
            calls += 1
            return calls == 1 ? 7 : nil
        }
    }
}
