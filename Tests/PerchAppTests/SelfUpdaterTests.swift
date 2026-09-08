import Testing
import Foundation
@testable import PerchApp

@MainActor
@Test func swapScriptWaitsThenReplacesAndRelaunches() {
    let script = SelfUpdater.swapScript(newApp: "/tmp/new/Perch.app", dest: "/Applications/Perch.app", pid: 4242)
    // Waits for our pid to exit before touching the running bundle.
    #expect(script.contains("kill -0 4242"))
    // Copies the new one in with ditto (paths quoted) and relaunches it.
    #expect(script.contains("ditto '/tmp/new/Perch.app' '/Applications/Perch.app'"))
    #expect(script.contains("open '/Applications/Perch.app'"))
    // If the swap fails, fall back to the release page.
    #expect(script.contains("else"))
}

@MainActor
@Test func swapScriptNeverDeletesTheAppBeforeVerifyingTheReplacement() {
    let script = SelfUpdater.swapScript(newApp: "/tmp/new/Perch.app", dest: "/Applications/Perch.app", pid: 4242)
    // The old bundle is moved to a backup, NOT deleted, before the copy.
    #expect(script.contains("mv '/Applications/Perch.app' \"$BAK\""))
    // The move-aside happens before the copy-in (so a failed copy can't leave nothing).
    let moveIdx = script.range(of: "mv '/Applications/Perch.app' \"$BAK\"")!.lowerBound
    let dittoIdx = script.range(of: "ditto '/tmp/new/Perch.app'")!.lowerBound
    #expect(moveIdx < dittoIdx)
    // On a failed copy it rolls the backup back, so the user is never left appless.
    #expect(script.contains("mv \"$BAK\" '/Applications/Perch.app'"))
}

@MainActor
@Test func shellQuoteEscapesEmbeddedQuotes() {
    // A path with a single quote must not break out of the quoting.
    #expect(SelfUpdater.shellQuote("/Users/a'b/Perch.app") == "'/Users/a'\\''b/Perch.app'")
    #expect(SelfUpdater.shellQuote("/plain/path") == "'/plain/path'")
}

@MainActor
@Test func bundleURLNilWhenUnbundled() {
    // Under `swift test` there's no .app bundle, so the updater reports it can't
    // self-swap (it falls back to opening the release page instead of corrupting
    // a non-existent bundle).
    #expect(SelfUpdater.bundleAppURL() == nil)
}
