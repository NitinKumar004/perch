import Foundation

/// Pure ordering math for drag-to-reorder, so the "where does it land" rule is
/// testable without a running panel.
public enum PanelReorder {
    /// The new id order after dropping `moving` onto `target`. Dropping onto a
    /// row lands just before it when moving up the list, and just after it when
    /// moving down — the natural feel of the gesture. Returns the input unchanged
    /// when the move is a no-op or either id is missing.
    public static func reordered(_ ids: [String], moving: String, target: String) -> [String] {
        guard moving != target,
              let from = ids.firstIndex(of: moving),
              let to = ids.firstIndex(of: target) else { return ids }
        var out = ids
        out.remove(at: from)
        let targetIndex = out.firstIndex(of: target) ?? out.count
        let insertAt = from < to ? targetIndex + 1 : targetIndex
        out.insert(moving, at: min(insertAt, out.count))
        return out
    }
}
