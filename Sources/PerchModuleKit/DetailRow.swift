import Foundation
import PerchCore

/// One line of detail a module contributes to the drop-down panel. This is the
/// "report" a module shows when the notch is opened — richer than the glanceable
/// pill. A row with a `url` is clickable and opens in the browser.
public struct DetailRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let tint: Tint
    public let symbolName: String?
    /// If set, the row is clickable and opens this URL.
    public let url: String?
    /// If set, the row renders a small trend graph (most-recent value last).
    public let sparkline: [Double]?

    public init(id: String, title: String, subtitle: String? = nil,
                tint: Tint = .neutral, symbolName: String? = nil,
                url: String? = nil, sparkline: [Double]? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.symbolName = symbolName
        self.url = url
        self.sparkline = sparkline
    }
}

/// A notification-worthy event a module raises on a state change (e.g. a build
/// turned red). The shell posts it as a native notification, deduped by `id`.
public struct ModuleAlert: Equatable, Sendable {
    /// Stable dedup key — the same alert fires at most once.
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// Everything a module produces for one update: the glanceable pill (for a slot)
/// and the detail rows (for the panel). The shell renders whichever it needs.
public struct ModuleRender: Equatable, Sendable {
    public let pill: PillContent
    public let detail: [DetailRow]
    /// An alert this update raises, if any (e.g. a build just turned red).
    public let alert: ModuleAlert?
    /// A short line naming what this module is watching (e.g. the repo it's
    /// scoped to, or the host it pings), shown under the panel row's title so
    /// the user always knows the source.
    public let contextLabel: String?

    public init(pill: PillContent, detail: [DetailRow], alert: ModuleAlert? = nil, contextLabel: String? = nil) {
        self.pill = pill
        self.detail = detail
        self.alert = alert
        self.contextLabel = contextLabel
    }
}
