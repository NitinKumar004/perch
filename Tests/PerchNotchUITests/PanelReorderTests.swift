import Testing
@testable import PerchNotchUI

/// The drag-to-reorder landing rule: move to an absolute index.
@Suite struct PanelReorderTests {
    let ids = ["a", "b", "c", "d"]

    @Test func movesToTheTop() {
        // The bug: a row could never reach index 0. Absolute placement can.
        #expect(PanelReorder.moved(ids, moving: "c", toIndex: 0) == ["c", "a", "b", "d"])
        #expect(PanelReorder.moved(ids, moving: "d", toIndex: 0) == ["d", "a", "b", "c"])
    }

    @Test func movesToTheBottom() {
        #expect(PanelReorder.moved(ids, moving: "a", toIndex: 3) == ["b", "c", "d", "a"])
        // Overshooting the count clamps to the end, never crashes.
        #expect(PanelReorder.moved(ids, moving: "a", toIndex: 99) == ["b", "c", "d", "a"])
    }

    @Test func movesToTheMiddle() {
        #expect(PanelReorder.moved(ids, moving: "a", toIndex: 2) == ["b", "c", "a", "d"])
        #expect(PanelReorder.moved(ids, moving: "d", toIndex: 1) == ["a", "d", "b", "c"])
    }

    @Test func isIdempotentNoFlipFlop() {
        // Placing a row at the index it already occupies is a no-op — applying the
        // same target twice yields the same order (the anti-flip-flop guarantee).
        let once = PanelReorder.moved(ids, moving: "b", toIndex: 1)
        #expect(once == ids)
        #expect(PanelReorder.moved(once, moving: "b", toIndex: 1) == ids)
    }

    @Test func negativeIndexClampsToTop() {
        #expect(PanelReorder.moved(ids, moving: "c", toIndex: -5) == ["c", "a", "b", "d"])
    }

    @Test func missingIdReturnsInput() {
        #expect(PanelReorder.moved(ids, moving: "x", toIndex: 0) == ids)
    }

    @Test func neverDropsOrDuplicates() {
        let out = PanelReorder.moved(ids, moving: "c", toIndex: 0)
        #expect(out.sorted() == ids.sorted())
        #expect(out.count == ids.count)
    }
}
