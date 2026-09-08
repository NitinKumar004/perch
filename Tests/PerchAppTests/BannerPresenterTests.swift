import Testing
import PerchNotchUI
@testable import PerchApp

/// The banner dwell scales with message length so a long, marquee-scrolling
/// banner stays on screen long enough to read instead of vanishing half-shown.
@Suite struct BannerPresenterTests {
    let base = 4.5, perChar = 0.09, max = 11.0

    func dwell(_ length: Int) -> Double {
        BannerPresenter.dwell(textLength: length, base: base, perCharacter: perChar, max: max)
    }

    @Test func longMessagesDwellLongerThanShortOnes() {
        let short = dwell(12)    // "up to date" — quick
        let long = dwell(70)     // "#2867 … · new review activity" — needs to scroll
        #expect(short < long)
        #expect(short >= base)   // never below the base dwell
    }

    @Test func dwellIsCappedForVeryLongMessages() {
        #expect(dwell(500) == max)      // capped, never lingers forever
        #expect(dwell(1000) == max)
    }

    @Test func exactScaling() {
        #expect(dwell(0) == base)                       // empty → base
        #expect(dwell(10) == base + 10 * perChar)       // linear in between
        #expect(dwell(-5) == base)                       // negative length clamped to 0
    }

    @Test func displayTextMatchesWhatTheBannerRenders() {
        // Title only when body empty; "title · body" otherwise — the length that
        // drives the dwell must match BannerView's own composition.
        #expect(BannerPresenter.displayText(BannerAlert(id: "a", title: "Hi", body: "", tint: .good, url: nil)) == "Hi")
        #expect(BannerPresenter.displayText(BannerAlert(id: "b", title: "#7 Fix", body: "approved", tint: .good, url: nil)) == "#7 Fix · approved")
    }
}
