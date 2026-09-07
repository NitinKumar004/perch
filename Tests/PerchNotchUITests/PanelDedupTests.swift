import Testing
@testable import PerchNotchUI

/// The panel's redundancy rules, exercised on the real module shapes that
/// prompted them (CPU/Memory/Disk restate themselves; Calendar and lists must
/// not be collapsed). Thermal is the counter-case: its pill is now a bar (empty
/// text) and its row title is a distinct level word ("Nominal"/"Serious"/…), so
/// the row is NOT a redundant echo of the "Thermal pressure" header.
@Suite struct PanelDedupTests {

    // MARK: header pill — strip a leading token that echoes the section title

    @Test func headerPillStripsTitlePrefix() {
        #expect(PanelDedup.headerPillText(title: "CPU", pillText: "CPU 40%") == "40%")
        #expect(PanelDedup.headerPillText(title: "Disk", pillText: "Disk 48.1 GB") == "48.1 GB")
    }

    @Test func headerPillKeepsUnrelatedText() {
        // Memory's pill says "RAM", not "Memory" — nothing to strip.
        #expect(PanelDedup.headerPillText(title: "Memory", pillText: "RAM 75%") == "RAM 75%")
        // Thermal's pill is now a bar (empty text) — nothing to strip, stays empty.
        #expect(PanelDedup.headerPillText(title: "Thermal pressure", pillText: "") == "")
        // A pill that is *only* the title never collapses to empty.
        #expect(PanelDedup.headerPillText(title: "CPU", pillText: "CPU") == "CPU")
    }

    // MARK: which rows are redundant restatements of the header

    @Test func metricSummaryRowsAreRedundant() {
        #expect(PanelDedup.titleIsRedundant(rowTitle: "CPU", headerTitle: "CPU", pillText: "CPU 40%"))
        #expect(PanelDedup.titleIsRedundant(rowTitle: "RAM", headerTitle: "Memory", pillText: "RAM 75%"))
        #expect(PanelDedup.titleIsRedundant(rowTitle: "Disk free", headerTitle: "Disk", pillText: "Disk 48.1 GB"))
    }

    @Test func informativeRowsAreNotRedundant() {
        // A meeting's name must survive — it's not the module name.
        #expect(!PanelDedup.titleIsRedundant(rowTitle: "Standup", headerTitle: "Next meeting", pillText: "in 8m"))
        // A PR title is its own content.
        #expect(!PanelDedup.titleIsRedundant(rowTitle: "#2418 Ship rate limiter", headerTitle: "Pull requests", pillText: "2 PRs"))
        // Thermal's real current shape: level-word row title, "Thermal pressure"
        // header, empty (bar) pill text. The row adds the word the pill dropped,
        // so it must NOT collapse as a redundant restatement of the header.
        #expect(!PanelDedup.titleIsRedundant(rowTitle: "Nominal", headerTitle: "Thermal pressure", pillText: ""))
    }

    // MARK: subtitle survives only when it adds something the pill lacks

    @Test func subtitleDroppedWhenPillAlreadySaysIt() {
        #expect(PanelDedup.novelSubtitle("40%", pillText: "CPU 40%") == nil)
        #expect(PanelDedup.novelSubtitle("75%", pillText: "RAM 75%") == nil)
    }

    @Test func subtitleKeptWhenItAddsInformation() {
        #expect(PanelDedup.novelSubtitle("48.1 GB free · 90% used", pillText: "Disk 48.1 GB") == "48.1 GB free · 90% used")
        // Thermal's bar pill carries no words, so its subtitle always adds info.
        #expect(PanelDedup.novelSubtitle("running cool", pillText: "") == "running cool")
        #expect(PanelDedup.novelSubtitle(nil, pillText: "") == nil)
    }
}
