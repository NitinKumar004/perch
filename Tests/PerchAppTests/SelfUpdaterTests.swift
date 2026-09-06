import Testing
import Foundation
@testable import PerchApp

@MainActor
@Test func swapScriptWaitsThenReplacesAndRelaunches() {
    let script = SelfUpdater.swapScript(newApp: "/tmp/new/Perch.app", dest: "/Applications/Perch.app", pid: 4242)
    // Waits for our pid to exit before touching the running bundle.
    #expect(script.contains("kill -0 4242"))
    // Replaces the old bundle and copies the new one in with ditto.
    #expect(script.contains("rm -rf '/Applications/Perch.app'"))
    #expect(script.contains("ditto '/tmp/new/Perch.app' '/Applications/Perch.app'"))
    // Relaunches the freshly-installed app.
    #expect(script.contains("open '/Applications/Perch.app'"))
}

@MainActor
@Test func bundleURLNilWhenUnbundled() {
    // Under `swift test` there's no .app bundle, so the updater reports it can't
    // self-swap (it falls back to opening the release page instead of corrupting
    // a non-existent bundle).
    #expect(SelfUpdater.bundleAppURL() == nil)
}
