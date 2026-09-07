import Testing
import PerchCore
import PerchModuleKit
@testable import PerchNotchUI

@Suite struct BannerPlacementTests {
    func pill(_ text: String) -> PillContent {
        PillContent(face: PillFace(text: text), freshness: .live, asOf: .init())
    }
    func combined(_ segs: [String]) -> PillContent {
        PillContent(face: PillFace(text: segs.joined(separator: " · "),
                                   segments: segs.map { FaceSegment(text: $0, tint: .good) }),
                    freshness: .live, asOf: .init())
    }

    @Test func weightIsTextLength() {
        #expect(BannerPlacement.weight(nil) == 0)
        #expect(BannerPlacement.weight(pill("6")) == 1)
        #expect(BannerPlacement.weight(pill("CPU 27%")) == 7)
        // A combined pill sums its segment texts, not the joined string.
        #expect(BannerPlacement.weight(combined(["CPU 27%", "RAM 61%"])) == 14)
    }

    @Test func bannerTakesTheBiggerSide() {
        // Right pill wider → banner on right.
        #expect(BannerPlacement.showOnRight(left: pill("6"), right: pill("CPU 27% · RAM 61%")))
        // Left pill wider → banner on left.
        #expect(!BannerPlacement.showOnRight(left: pill("Pull requests 6"), right: pill("up")))
    }

    @Test func tiesAndEmptySidesFavourRight() {
        #expect(BannerPlacement.showOnRight(left: pill("ab"), right: pill("cd")))   // tie → right
        #expect(BannerPlacement.showOnRight(left: nil, right: nil))                 // both empty → right
        #expect(BannerPlacement.showOnRight(left: pill("x"), right: nil) == false)  // only left has content → left
    }
}
