import Testing
@testable import PerchNotchUI

/// Long-list collapse rules for the panel.
@Suite struct PanelCollapseTests {

    @Test func shortListsAreNotCollapsible() {
        #expect(!PanelCollapse.isCollapsible(total: 0, limit: 3))
        #expect(!PanelCollapse.isCollapsible(total: 3, limit: 3))
    }

    @Test func longerThanLimitIsCollapsible() {
        #expect(PanelCollapse.isCollapsible(total: 4, limit: 3))
    }

    @Test func collapsedShowsPreviewLimit() {
        // 6 rows, collapsed → show the preview count.
        #expect(PanelCollapse.visibleCount(total: 6, expanded: false, limit: 3) == 3)
    }

    @Test func expandedShowsEverything() {
        #expect(PanelCollapse.visibleCount(total: 6, expanded: true, limit: 3) == 6)
    }

    @Test func shortListShowsAllRegardlessOfState() {
        // Nothing to hide → visible count is the total, collapsed or not.
        #expect(PanelCollapse.visibleCount(total: 2, expanded: false, limit: 3) == 2)
        #expect(PanelCollapse.visibleCount(total: 2, expanded: true, limit: 3) == 2)
    }
}
