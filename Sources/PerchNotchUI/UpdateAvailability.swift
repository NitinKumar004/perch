import Foundation

/// The update state shown in the panel footer, so the whole update flow is
/// reachable from the notch panel — never only from the menu-bar icon, which a
/// crowded menu bar or the notch can hide.
public enum UpdateAvailability: Sendable, Equatable {
    /// Nothing checked yet / no update pending — the button invites a check.
    case idle
    /// A check is in flight.
    case checking
    /// A newer version was found and can be installed now.
    case available(version: String)
    /// The found update is downloading + swapping in.
    case downloading(version: String)
    /// Checked, and we're already current.
    case upToDate
    /// The in-place swap isn't possible — offer the release page instead.
    case releasePage(version: String)

    /// The footer button's label for this state.
    public var buttonTitle: String {
        switch self {
        case .idle:                 return "Check for Updates"
        case .checking:             return "Checking…"
        case .available(let v):     return "Update to \(v)"
        case .downloading(let v):   return "Downloading \(v)…"
        case .upToDate:             return "Up to date"
        case .releasePage(let v):   return "Get \(v)"
        }
    }

    /// SF Symbol paired with the label.
    public var symbolName: String {
        switch self {
        case .idle, .upToDate:      return "arrow.down.circle"
        case .checking:             return "arrow.triangle.2.circlepath"
        case .available:            return "arrow.down.circle.fill"
        case .downloading:          return "arrow.down.circle"
        case .releasePage:          return "safari"
        }
    }

    /// Whether tapping does something. Transient/terminal states (checking,
    /// downloading) are shown but not tappable. "Up to date" stays tappable so
    /// the user can re-check whenever they want — it just runs the check again.
    public var isActionable: Bool {
        switch self {
        case .checking, .downloading:                     return false
        case .idle, .available, .releasePage, .upToDate:  return true
        }
    }

    /// An available update is highlighted (accent) to draw the eye; every other
    /// state is quiet.
    public var isHighlighted: Bool {
        if case .available = self { return true }
        return false
    }

    /// The newest release version this state has learned about, if any — for an
    /// always-visible "latest vX" hint next to the running version. `.upToDate`
    /// returns nil here because the newest version equals the one you're running
    /// (the caller supplies the current version for that case); `.idle`/`.checking`
    /// haven't learned a version yet.
    public var offeredVersion: String? {
        switch self {
        case .available(let v), .downloading(let v), .releasePage(let v): return v
        case .idle, .checking, .upToDate: return nil
        }
    }

    /// Whether a check has completed and we're confirmed current.
    public var isUpToDate: Bool {
        if case .upToDate = self { return true }
        return false
    }
}
