import Testing
import PerchNotchUI
@testable import PerchApp

/// The banner dwell scales with message length so a long, marquee-scrolling
/// banner stays on screen long enough to read instead of vanishing half-shown.
@Suite struct BannerPresenterTests {
    let base = 3.5, max = 20.0

    func dwell(_ length: Int) -> Double {
        BannerPresenter.dwell(textLength: length, base: base, max: max)
    }

    @Test func aFittingMessageJustUsesTheBaseDwell() {
        // Short enough to not overflow the slot → no scroll → base dwell.
        #expect(dwell(12) == base)
        #expect(dwell(0) == base)
        #expect(dwell(-5) == base)   // negative clamped
    }

    @Test func anOverflowingMessageStaysForItsFullMarqueeReveal() {
        let length = 80   // overflows → must scroll to be fully seen
        let reveal = MarqueeTiming.bannerRevealSeconds(textLength: length)
        #expect(reveal > 0)                       // it really does overflow
        #expect(dwell(length) >= reveal)          // dwell covers the whole reveal
        #expect(dwell(length) > base)             // and is longer than a short one
        #expect(dwell(40) < dwell(120))           // longer message → longer dwell
    }

    @Test func dwellIsCappedForAPathologicalRunOn() {
        #expect(dwell(1000) == max)   // bounded, never lingers forever
    }

    @Test func reduceMotionUsesBaseDwellSinceNothingScrolls() {
        // A long message that would normally get a long reveal dwell — but under
        // Reduce Motion it just truncates, so it must NOT linger for a scroll.
        let long = BannerPresenter.dwell(textLength: 120, base: base, max: max, reduceMotion: true)
        #expect(long == base)
        #expect(long < BannerPresenter.dwell(textLength: 120, base: base, max: max, reduceMotion: false))
    }

    @Test func displayTextMatchesWhatTheBannerRenders() {
        // Title only when body empty; "title · body" otherwise — the length that
        // drives the dwell must match BannerView's own composition.
        #expect(BannerPresenter.displayText(BannerAlert(id: "a", title: "Hi", body: "", tint: .good, url: nil)) == "Hi")
        #expect(BannerPresenter.displayText(BannerAlert(id: "b", title: "#7 Fix", body: "approved", tint: .good, url: nil)) == "#7 Fix · approved")
    }
}
