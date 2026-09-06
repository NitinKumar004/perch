import Testing
import Foundation
import PerchCore
import PerchModuleKit
@testable import PerchModules

// MARK: - Timer

@Test func timerFormatsRemaining() {
    #expect(TimerModule.format(1500) == "25:00")
    #expect(TimerModule.format(65) == "1:05")
    #expect(TimerModule.format(9) == "0:09")
}

@Test func timerFaceDoneAtZero() {
    let m = TimerModule(controller: TimerController())
    func s(_ r: Int, paused: Bool = false) -> TimerState { TimerState(remaining: r, isPaused: paused, id: "25") }
    #expect(m.face(for: s(0), in: .rightPill).tint == .good)
    #expect(m.face(for: s(300), in: .rightPill).tint == .accent)
    #expect(m.face(for: s(300), in: .rightPill).text == "5:00")
    // Detail rows expose pause + reset controls.
    let rows = m.detail(for: s(300))
    #expect(rows.contains { $0.action == "timer.toggle:25" })
    #expect(rows.contains { $0.action == "timer.reset:25" })
    #expect(m.face(for: s(300, paused: true), in: .rightPill).symbolName == "pause.circle")
}

@Test func timerControllerPausesAndResets() async {
    let c = TimerController()
    let t0 = Date(timeIntervalSince1970: 1000)
    // 10s elapse while running.
    _ = await c.elapsed(id: "x", now: t0)
    let e1 = await c.elapsed(id: "x", now: t0.addingTimeInterval(10))
    #expect(Int(e1.elapsed) == 10)
    // Pause at t0+10, then 100s of wall time pass — elapsed stays ~10.
    await c.togglePause(id: "x", now: t0.addingTimeInterval(10))
    let paused = await c.elapsed(id: "x", now: t0.addingTimeInterval(110))
    #expect(paused.isPaused)
    #expect(Int(paused.elapsed) == 10)
    // Reset → back to zero, running.
    await c.reset(id: "x", now: t0.addingTimeInterval(110))
    let afterReset = await c.elapsed(id: "x", now: t0.addingTimeInterval(115))
    #expect(!afterReset.isPaused)
    #expect(Int(afterReset.elapsed) == 5)
}

// MARK: - Deploy / health probe

@Test func healthProbeClassifiesStatus() async {
    let ok = HealthProbe { _ in 200 }
    let bad = HealthProbe { _ in 503 }
    let dead = HealthProbe { _ in nil }
    let url = URL(string: "https://example.com/health")!

    #expect(await ok.check(url) == .healthy)
    #expect(await bad.check(url) == .degraded)
    #expect(await dead.check(url) == .down)
}

@Test func deployFaceColors() {
    let m = DeployModule()
    #expect(m.face(for: .healthy, in: .leftPill).tint == .good)
    #expect(m.face(for: .degraded, in: .leftPill).tint == .warning)
    #expect(m.face(for: .down, in: .leftPill).tint == .critical)
}
