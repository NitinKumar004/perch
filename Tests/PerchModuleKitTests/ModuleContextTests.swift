import Testing
import PerchCore
@testable import PerchModuleKit

/// The settings-parsing surface every module relies on for its cadence and
/// user-tunable options. These are load-bearing: a broken clamp would let a typo
/// hammer a source, a broken parse would silently drop a user's choice.
@Suite struct ModuleContextTests {
    func ctx(_ settings: [String: String]) -> ModuleContext { ModuleContext(settings: settings) }

    @Test func refreshSecondsFallsBackAndClamps() {
        #expect(ctx([:]).refreshSeconds(fallback: 60) == 60)               // unset → fallback
        #expect(ctx(["refreshSeconds": "x"]).refreshSeconds(fallback: 60) == 60)  // unparseable → fallback
        #expect(ctx(["refreshSeconds": "90"]).refreshSeconds(fallback: 60) == 90) // honored
        #expect(ctx(["refreshSeconds": "1"]).refreshSeconds(fallback: 60, minimum: 30) == 30) // clamped up
    }

    @Test func settingTreatsBlankAsDefault() {
        #expect(ctx([:]).setting("dir", fallback: "~/.claude") == "~/.claude")
        #expect(ctx(["dir": ""]).setting("dir", fallback: "~/.claude") == "~/.claude")  // blank = default
        #expect(ctx(["dir": "/x"]).setting("dir", fallback: "~/.claude") == "/x")
    }

    @Test func boolIsTolerantOfCommonTruthyValues() {
        #expect(ctx([:]).bool("on", fallback: true) == true)         // unset → fallback
        #expect(ctx([:]).bool("on", fallback: false) == false)
        for truthy in ["true", "True", "TRUE", "1", "yes", "on"] {
            #expect(ctx(["on": truthy]).bool("on", fallback: false) == true)
        }
        for falsy in ["false", "False", "0", "no", "off", "nonsense"] {
            #expect(ctx(["on": falsy]).bool("on", fallback: true) == false)
        }
    }

    @Test func intFallsBackAndClampsToRange() {
        #expect(ctx([:]).int("n", fallback: 10) == 10)                          // unset → fallback
        #expect(ctx(["n": "x"]).int("n", fallback: 10) == 10)                   // unparseable → fallback
        #expect(ctx(["n": "50"]).int("n", fallback: 10, minimum: 1, maximum: 100) == 50)
        #expect(ctx(["n": "0"]).int("n", fallback: 10, minimum: 1, maximum: 100) == 1)    // clamped up
        #expect(ctx(["n": "999"]).int("n", fallback: 10, minimum: 1, maximum: 100) == 100) // clamped down
    }
}
