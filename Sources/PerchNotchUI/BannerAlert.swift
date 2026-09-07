import Foundation
import PerchCore

/// A transient alert shown *in the notch* — slides down, sits briefly, springs
/// back to the pills. The in-HUD counterpart to a macOS notification banner, so
/// an alert is felt on the notch itself, not only in the corner of the screen.
public struct BannerAlert: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    /// Severity colour (from the triggering module's pill tint).
    public let tint: Tint
    /// Optional deep link (the failing build, the PR) — tapping opens it.
    public let url: String?

    public init(id: String, title: String, body: String, tint: Tint, url: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.tint = tint
        self.url = url
    }

    /// An SF Symbol for the severity — a quick glyph before the text.
    public var symbolName: String {
        switch tint {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning:  return "exclamationmark.circle.fill"
        case .good:     return "checkmark.circle.fill"
        case .info:     return "info.circle.fill"
        case .accent:   return "sparkles"
        case .neutral:  return "bell.fill"
        }
    }
}
