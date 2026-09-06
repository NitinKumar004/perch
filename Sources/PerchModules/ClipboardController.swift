import Foundation

/// The on-device store of recent clipboard text. Shared, like `TimerController`,
/// so the module can read history while the app writes a chosen entry back to
/// the system pasteboard when a panel row is clicked.
///
/// Everything here stays in memory — clipboard contents are never written to
/// disk — honouring the "local only, nothing leaves the Mac" principle.
public actor ClipboardController {
    private var entries: [String] = []   // most-recent first
    private let cap: Int

    public init(cap: Int = 12) { self.cap = cap }

    /// Record a newly-copied string. No-ops on empty text or an unchanged top
    /// entry; a repeat of an older entry moves it back to the top.
    public func record(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entries.first != trimmed else { return }
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        if entries.count > cap { entries.removeLast(entries.count - cap) }
    }

    public func snapshot() -> [String] { entries }

    public func entry(at index: Int) -> String? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    public func clear() { entries.removeAll() }
}
