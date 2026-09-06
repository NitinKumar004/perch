import Foundation

/// A minimal semantic-version comparison — enough to answer "is the latest
/// release newer than what I'm running?" without a dependency. Tolerant of a
/// leading "v" and of missing components ("1.2" == "1.2.0").
public struct SemanticVersion: Comparable, Sendable, Equatable {
    public let components: [Int]

    /// Parse "v1.2.3" / "1.2" / "1.2.3-beta". Returns nil if there's no leading
    /// numeric version at all. A pre-release suffix after "-" is ignored for
    /// ordering (good enough for an update prompt).
    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let noPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst()) : trimmed
        let core = noPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? noPrefix
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = Swift.max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    // Equality is value-based, not array-shape-based, so "1.2" == "1.2.0".
    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    /// Is `candidate` a strictly newer version than `current`? Unparseable
    /// inputs are treated as "not newer" so a bad tag never nags the user.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let c = SemanticVersion(candidate), let base = SemanticVersion(current) else { return false }
        return c > base
    }
}
