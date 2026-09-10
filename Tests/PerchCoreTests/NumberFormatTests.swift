import Testing
@testable import PerchCore

@Suite struct NumberFormatTests {
    @Test func compactScalesThroughTiers() {
        #expect(NumberFormat.compact(500) == "500")
        #expect(NumberFormat.compact(12_300) == "12.3K")
        #expect(NumberFormat.compact(76_775_798) == "76.8M")
        #expect(NumberFormat.compact(3_463_018_827) == "3.5B")
    }

    @Test func compactIsWholeBelowFirstTierAndAt100() {
        #expect(NumberFormat.compact(0) == "0")
        #expect(NumberFormat.compact(999) == "999")     // raw count, no decimal
        #expect(NumberFormat.compact(150_000) == "150K") // ≥100 within a tier → whole
    }

    @Test func compactRoundsBeforeChoosingTier() {
        // 999_950 rounds to 1000K → must roll up to "1.0M", never "1000.0K".
        #expect(NumberFormat.compact(999_950) == "1.0M")
        #expect(NumberFormat.compact(999_999_999_999) == "1.0T")
    }

    @Test func compactClampsNegativesToZero() {
        #expect(NumberFormat.compact(-5) == "0")
    }
}
