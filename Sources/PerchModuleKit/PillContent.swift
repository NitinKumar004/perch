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
    /// Optional per-segment colouring: when set, the shell renders each segment
    /// in its OWN tint (e.g. a combined pill where CPU, RAM and network each keep
    /// their own status colour). `text`/`tint` remain the single-colour fallback
    /// (used for the menu-bar status icon and any non-segment context).
    public let segments: [FaceSegment]?
    /// An optional small "attention" dot after the text, in this tint — a calm,
    /// glanceable "you have something to act on" signal that avoids shouting a
    /// raw number (the exact figure belongs in the tooltip / panel). nil = none.
    public let badge: Tint?
    /// An optional 0…1 level rendered as a small filled bar in the pill — a
    /// glanceable gauge (e.g. thermal pressure) that reads without a jargon word:
    /// nearly-empty = fine, full = maxed. Shown in the pill's `tint`. nil = none.
    public let progress: Double?

    public init(text: String, symbolName: String? = nil, tint: Tint = .neutral,
                tooltip: String? = nil, segments: [FaceSegment]? = nil,
                badge: Tint? = nil, progress: Double? = nil) {
        self.text = text
        self.symbolName = symbolName
        self.tint = tint
        self.tooltip = tooltip
        self.segments = segments
        self.badge = badge
        self.progress = progress
    }
}

/// One coloured piece of a multi-part pill face. Usually text; a member that
/// renders as a bar rather than a word (e.g. thermal pressure) carries a
/// `progress` (0…1) instead, so a combined pill can show its little gauge inline.
public struct FaceSegment: Equatable, Sendable {
    public let text: String
    public let tint: Tint
    /// If set, this segment renders as a small bar (0…1) instead of text — for a
    /// member like thermal pressure that reads better as a gauge than a word.
    public let progress: Double?
    public init(text: String, tint: Tint, progress: Double? = nil) {
        self.text = text
        self.tint = tint
        self.progress = progress
    }
}

public extension ModuleDescriptor {
    /// A neutral placeholder face used to seed a panel row before the module's
    /// first real value arrives, so row ordering is stable.
    var placeholderFace: PillFace {
        PillFace(text: name, symbolName: nil, tint: .neutral, tooltip: summary)
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
