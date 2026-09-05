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
    let m = TimerModule()
    #expect(m.face(for: 0, in: .rightPill).tint == .good)
    #expect(m.face(for: 300, in: .rightPill).tint == .accent)
    #expect(m.face(for: 300, in: .rightPill).text == "5:00")
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
