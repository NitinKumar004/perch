import Testing
import Foundation
import PerchCore
@testable import PerchModuleKit

/// A fake module that emits a scripted sequence of snapshots and alerts on ANY
/// value change — so a spurious alert is easy to detect.
private struct FakeAlertModule: NotchModule {
    typealias State = Int
    let snapshots: [Snapshot<Int>]

    static let descriptor = ModuleDescriptor(
        id: "test.fake", name: "Fake", summary: "",
        supportedSlots: [.leftPill], requiresConnection: false)

    func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<Int>> {
        AsyncStream { continuation in
            for s in snapshots { continuation.yield(s) }
            continuation.finish()
        }
    }
    func face(for value: Int, in slot: Slot) -> PillFace { PillFace(text: "\(value)") }
    func notification(for value: Int, previous: Int?) -> ModuleAlert? {
        guard let previous, previous != value else { return nil }
        return ModuleAlert(id: "chg-\(previous)-\(value)", title: "changed", body: "")
    }
}

@Suite struct AnyNotchModuleTests {
    private func collectAlerts(_ snapshots: [Snapshot<Int>]) async -> [ModuleAlert] {
        let m = AnyNotchModule(FakeAlertModule(snapshots: snapshots))
        var alerts: [ModuleAlert] = []
        for await render in m.renderStream(ModuleContext(), slot: .leftPill) {
            if let a = render.alert { alerts.append(a) }
        }
        return alerts
    }

    @Test func seedAndFirstLiveNeverAlert_onlyGenuineTransitionsDo() async {
        let now = Date()
        // seed (non-live), first live is ALREADY bad (9), then a genuine change 9→5.
        let alerts = await collectAlerts([
            Snapshot(value: 0, freshness: .unknown, asOf: now),   // placeholder seed
            Snapshot(value: 9, freshness: .live, asOf: now),      // already-bad → baseline, no alert
            Snapshot(value: 5, freshness: .live, asOf: now),      // real change → one alert
        ])
        #expect(alerts.map(\.id) == ["chg-9-5"])   // exactly one, only the genuine transition
    }

    @Test func nonLiveRendersDoNotDiffOrMoveBaseline() async {
        let now = Date()
        // live 3 baseline; a stale 8 (must be ignored); back to live 8 → genuine 3→8.
        let alerts = await collectAlerts([
            Snapshot(value: 3, freshness: .live, asOf: now),
            Snapshot(value: 8, freshness: .stale(since: now), asOf: now),  // ignored
            Snapshot(value: 8, freshness: .live, asOf: now),               // 3→8 genuine
        ])
        #expect(alerts.map(\.id) == ["chg-3-8"])
    }

    @Test func alertsFireOnEveryLiveTransition() async {
        let now = Date()
        let alerts = await collectAlerts([
            Snapshot(value: 1, freshness: .live, asOf: now),   // baseline
            Snapshot(value: 2, freshness: .live, asOf: now),   // 1→2
            Snapshot(value: 2, freshness: .live, asOf: now),   // no change
            Snapshot(value: 3, freshness: .live, asOf: now),   // 2→3
        ])
        #expect(alerts.map(\.id) == ["chg-1-2", "chg-2-3"])
    }
}
