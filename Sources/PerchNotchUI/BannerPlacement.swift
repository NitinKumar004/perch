import Foundation
import PerchModuleKit

/// Decides which pill a transient banner takes over — the *bigger* one (more
/// text), so the other, smaller pill stays put. Pure, so the tie-break and
/// nil-pill handling are testable without a running view.
enum BannerPlacement {
    /// The rendered-text length of a pill — a combined pill sums its segments.
    /// nil (no pill) weighs 0.
    static func weight(_ content: PillContent?) -> Int {
        guard let face = content?.face else { return 0 }
        if let segments = face.segments { return segments.reduce(0) { $0 + $1.text.count } }
        return face.text.count
    }

    /// Whether the banner shows on the RIGHT of the notch. Ties (and two empty
    /// sides) favour the right — the leading side just past the notch, where the
    /// wider pills usually sit.
    static func showOnRight(left: PillContent?, right: PillContent?) -> Bool {
        weight(right) >= weight(left)
    }
}
