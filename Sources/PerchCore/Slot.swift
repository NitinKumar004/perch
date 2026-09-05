import Foundation

/// A position in the notch HUD that a module can occupy.
///
/// The shell owns exactly these positions; a module declares which ones it
/// supports and the user's layout binds a module to a slot. Keeping the set
/// small and fixed is what lets the shell render any module without knowing
/// what it is.
public enum Slot: String, Codable, Sendable, CaseIterable {
    /// The single glanceable pill immediately left of the notch.
    case leftPill
    /// The single glanceable pill immediately right of the notch.
    case rightPill
    /// A stacked row inside the panel that opens on hover.
    case panel
}
