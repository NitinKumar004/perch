import Foundation

/// Pure rules for collapsing a long detail list (a big PR list, many builds) to
/// a short preview with an expand/collapse toggle, so one module can't dominate
/// the panel. Testable without a running view.
enum PanelCollapse {
    /// How many rows to show when collapsed.
    static let previewLimit = 3

    /// A list is collapsible only when it has more rows than the preview shows —
    /// otherwise there's nothing to hide and no toggle is offered.
    static func isCollapsible(total: Int, limit: Int = previewLimit) -> Bool {
        total > limit
    }

    /// How many rows to render: everything when expanded or short, else the
    /// preview count.
    static func visibleCount(total: Int, expanded: Bool, limit: Int = previewLimit) -> Int {
        (expanded || !isCollapsible(total: total, limit: limit)) ? total : limit
    }
}
