/// The rule for whether an auto-open's auto-close, once its countdown fires,
/// should actually close the panel. Extracted so the invariant is unit-testable
/// without driving the async timer: only close a panel that is still open AND is
/// still an auto-open peek — never one the user has since taken control of
/// (toggled, opened Settings) or already closed.
enum AutoClose {
    /// Close only a panel that is still open, still an auto-open peek, and NOT
    /// currently being read (pointer over it) — so a second red event mid-read
    /// can never re-arm a close that yanks the panel away while you're hovering.
    static func shouldClose(panelOpen: Bool, autoOpened: Bool, hovering: Bool) -> Bool {
        panelOpen && autoOpened && !hovering
    }
}
