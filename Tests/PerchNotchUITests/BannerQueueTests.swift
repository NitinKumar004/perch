import Testing
import PerchCore
@testable import PerchNotchUI

/// (`enqueue`/`advance` mutate, so results are captured to locals before `#expect`.)
@Suite struct BannerQueueTests {
    func banner(_ id: String) -> BannerAlert {
        BannerAlert(id: id, title: id, body: "", tint: .warning)
    }

    @Test func firstBannerShowsImmediately() {
        var q = BannerQueue()
        let shownNow = q.enqueue(banner("a"))     // nothing showing → show now
        #expect(shownNow)
        #expect(q.current?.id == "a")
        #expect(q.pendingCount == 0)
    }

    @Test func secondBannerQueuesBehindFirst() {
        var q = BannerQueue()
        _ = q.enqueue(banner("a"))
        let queued = q.enqueue(banner("b"))       // one already showing → queue
        #expect(!queued)
        #expect(q.current?.id == "a")
        #expect(q.pendingCount == 1)
    }

    @Test func advancePromotesNextThenEmpties() {
        var q = BannerQueue()
        _ = q.enqueue(banner("a"))
        _ = q.enqueue(banner("b"))
        let next = q.advance()                    // a's time up → show b
        #expect(next?.id == "b")
        #expect(q.current?.id == "b")
        let empty = q.advance()                   // b's time up → nothing left
        #expect(empty == nil)
        #expect(q.current == nil)
        #expect(q.isEmpty)
    }

    @Test func duplicateIdsAreIgnored() {
        var q = BannerQueue()
        _ = q.enqueue(banner("a"))
        let dupCurrent = q.enqueue(banner("a"))   // same as current → ignored
        _ = q.enqueue(banner("b"))
        let dupPending = q.enqueue(banner("b"))   // same as pending → ignored
        #expect(!dupCurrent)
        #expect(!dupPending)
        #expect(q.pendingCount == 1)
    }

    @Test func bannerSymbolBySeverity() {
        #expect(BannerAlert(id: "1", title: "t", body: "", tint: .critical).symbolName == "exclamationmark.triangle.fill")
        #expect(BannerAlert(id: "2", title: "t", body: "", tint: .good).symbolName == "checkmark.circle.fill")
    }
}
