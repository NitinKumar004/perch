import Foundation
import PerchCore

/// What a module wants a pill to *look like* — declared, not drawn.
///
/// Modules return a `PillFace` describing meaning (text, an optional SF Symbol,
/// a semantic tint). They never touch SwiftUI, so they stay pure and testable
/// and the shell owns every pixel of chrome.
public struct PillFace: Equatable, Sendable {
    public let text: String
    public let symbolName: String?
    public let tint: Tint
    public let tooltip: String?

    public init(text: String, symbolName: String? = nil, tint: Tint = .neutral, tooltip: String? = nil) {
        self.text = text
        self.symbolName = symbolName
        self.tint = tint
        self.tooltip = tooltip
    }
}

/// A fully resolved thing to render: the module's `PillFace` plus the freshness
/// the shell needs to style honestly (dim + "2m" when stale, a spinner when
/// computing, and so on). This is the only type the shell consumes from a
/// module — the module's own `State` never leaks past the SDK boundary.
public struct PillContent: Equatable, Sendable {
    public let face: PillFace
    public let freshness: Freshness
    public let asOf: Date

    public init(face: PillFace, freshness: Freshness, asOf: Date) {
        self.face = face
        self.freshness = freshness
        self.asOf = asOf
    }
}
