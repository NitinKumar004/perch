import Foundation

/// Pure de-duplication rules for the detail panel.
///
/// A single-metric module states itself three times — the section title
/// ("CPU"), the pill ("CPU 40%") and a detail row ("CPU" / "40%"). These helpers
/// let the panel show each fact once while leaving genuinely informative rows
/// (a meeting's name, a PR title, a list) fully intact. All string-pure, so the
/// logic is testable without a running view.
enum PanelDedup {

    /// The pill text to show in the panel header. Strips a leading token equal to
    /// the section title so the pill doesn't echo the label beside it:
    /// title "CPU" + "CPU 40%" → "40%"; title "Disk" + "Disk 48.1 GB" → "48.1 GB".
    /// Leaves the text untouched when it doesn't start with the title (title
    /// "Memory" + "RAM 75%" stays "RAM 75%") or when stripping would empty it.
    static func headerPillText(title: String, pillText: String) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return pillText }
        let prefix = t.lowercased() + " "
        guard pillText.lowercased().hasPrefix(prefix) else { return pillText }
        let stripped = String(pillText.dropFirst(t.count)).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? pillText : stripped
    }

    /// Whether a detail row's *title* merely restates the header (its section
    /// title or pill), so the row is a summary of what's already shown rather
    /// than new information. Case-insensitive, matches either direction of
    /// containment ("Disk free" ⊃ "Disk", "CPU" ⊂ pill "CPU 40%").
    static func titleIsRedundant(rowTitle: String, headerTitle: String, pillText: String) -> Bool {
        let t = rowTitle.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return true }   // nothing to say → redundant
        let h = headerTitle.lowercased().trimmingCharacters(in: .whitespaces)
        let p = pillText.lowercased()
        if !h.isEmpty, h.contains(t) || t.contains(h) { return true }
        return p.contains(t)
    }

    /// The row subtitle to keep when its title has been dropped as redundant —
    /// but only if it carries something the pill doesn't already show. Disk's
    /// "48.1 GB free · 90% used" survives (the pill only says "48.1 GB"); CPU's
    /// "40%" is dropped (the pill already says "40%").
    static func novelSubtitle(_ subtitle: String?, pillText: String) -> String? {
        guard let s = subtitle?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return pillText.lowercased().contains(s.lowercased()) ? nil : s
    }
}
