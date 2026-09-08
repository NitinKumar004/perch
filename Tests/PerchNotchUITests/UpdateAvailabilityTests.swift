import Testing
@testable import PerchNotchUI

/// The panel footer's update control derives its label, actionability, and
/// emphasis purely from `UpdateAvailability`. These lock that mapping so the
/// footer never shows, say, a tappable "Downloading…" or a plain "Update to X".
@Suite struct UpdateAvailabilityTests {

    @Test func buttonTitleForEachState() {
        #expect(UpdateAvailability.idle.buttonTitle == "Check for Updates")
        #expect(UpdateAvailability.checking.buttonTitle == "Checking…")
        #expect(UpdateAvailability.available(version: "1.2.0").buttonTitle == "Update to 1.2.0")
        #expect(UpdateAvailability.downloading(version: "1.2.0").buttonTitle == "Downloading 1.2.0…")
        #expect(UpdateAvailability.upToDate.buttonTitle == "Up to date")
        #expect(UpdateAvailability.releasePage(version: "1.2.0").buttonTitle == "Get 1.2.0")
    }

    @Test func onlyInFlightStatesAreInert() {
        // Something to act on → tappable.
        #expect(UpdateAvailability.idle.isActionable)
        #expect(UpdateAvailability.available(version: "1.2.0").isActionable)
        #expect(UpdateAvailability.releasePage(version: "1.2.0").isActionable)
        // "Up to date" stays tappable so the user can re-check on demand.
        #expect(UpdateAvailability.upToDate.isActionable)
        // Only work in flight is inert (no double-tap into a running check/install).
        #expect(!UpdateAvailability.checking.isActionable)
        #expect(!UpdateAvailability.downloading(version: "1.2.0").isActionable)
    }

    @Test func onlyAvailableIsHighlighted() {
        #expect(UpdateAvailability.available(version: "1.2.0").isHighlighted)
        #expect(!UpdateAvailability.idle.isHighlighted)
        #expect(!UpdateAvailability.checking.isHighlighted)
        #expect(!UpdateAvailability.downloading(version: "1.2.0").isHighlighted)
        #expect(!UpdateAvailability.upToDate.isHighlighted)
        #expect(!UpdateAvailability.releasePage(version: "1.2.0").isHighlighted)
    }

    @Test func everyStateHasASymbol() {
        let states: [UpdateAvailability] = [
            .idle, .checking, .available(version: "1"), .downloading(version: "1"),
            .upToDate, .releasePage(version: "1"),
        ]
        for state in states {
            #expect(!state.symbolName.isEmpty)
        }
    }
}
