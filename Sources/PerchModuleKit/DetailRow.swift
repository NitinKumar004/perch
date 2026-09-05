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

    public init(id: String, title: String, subtitle: String? = nil,
                tint: Tint = .neutral, symbolName: String? = nil, url: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.symbolName = symbolName
        self.url = url
    }
}

/// Everything a module produces for one update: the glanceable pill (for a slot)
/// and the detail rows (for the panel). The shell renders whichever it needs.
public struct ModuleRender: Equatable, Sendable {
    public let pill: PillContent
    public let detail: [DetailRow]

    public init(pill: PillContent, detail: [DetailRow]) {
        self.pill = pill
        self.detail = detail
    }
}
