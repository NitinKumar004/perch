import Foundation

/// Pure ordering math for drag-to-reorder, so the "where does it land" rule is
/// testable without a running panel.
public enum PanelReorder {
    /// Move `moving` to an ABSOLUTE `toIndex` in the id list (clamped to a valid
    /// slot). Absolute placement is idempotent — the same target index always
    /// yields the same result — so a continuous drag settles at that slot instead
    /// of flip-flopping between two neighbours as the dragged row passes one, and
    /// index 0 puts it at the very top. Returns the input unchanged when `moving`
    /// isn't present.
    public static func moved(_ ids: [String], moving: String, toIndex: Int) -> [String] {
        guard let from = ids.firstIndex(of: moving) else { return ids }
        var out = ids
        out.remove(at: from)
        out.insert(moving, at: max(0, min(toIndex, out.count)))
        return out
    }
}
