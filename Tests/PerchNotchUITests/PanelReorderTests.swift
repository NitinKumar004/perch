import Testing
@testable import PerchNotchUI

/// The drag-to-reorder landing rule.
@Suite struct PanelReorderTests {
    let ids = ["a", "b", "c", "d"]

    @Test func movingDownLandsAfterTarget() {
        // Drag "a" onto "c" (downward) → a sits just after c.
        #expect(PanelReorder.reordered(ids, moving: "a", target: "c") == ["b", "c", "a", "d"])
    }

    @Test func movingUpLandsBeforeTarget() {
        // Drag "d" onto "b" (upward) → d sits just before b.
        #expect(PanelReorder.reordered(ids, moving: "d", target: "b") == ["a", "d", "b", "c"])
    }

    @Test func adjacentSwap() {
        #expect(PanelReorder.reordered(ids, moving: "b", target: "a") == ["b", "a", "c", "d"])
        #expect(PanelReorder.reordered(ids, moving: "a", target: "b") == ["b", "a", "c", "d"])
    }

    @Test func movingToEnds() {
        #expect(PanelReorder.reordered(ids, moving: "a", target: "d") == ["b", "c", "d", "a"])
        #expect(PanelReorder.reordered(ids, moving: "d", target: "a") == ["d", "a", "b", "c"])
    }

    @Test func noOpsReturnInput() {
        #expect(PanelReorder.reordered(ids, moving: "b", target: "b") == ids)
        #expect(PanelReorder.reordered(ids, moving: "x", target: "b") == ids)
        #expect(PanelReorder.reordered(ids, moving: "a", target: "z") == ids)
    }

    @Test func orderIsPreservedInLength() {
        let out = PanelReorder.reordered(ids, moving: "c", target: "a")
        #expect(out.sorted() == ids.sorted())   // no dupes, no drops
        #expect(out.count == ids.count)
    }
}
