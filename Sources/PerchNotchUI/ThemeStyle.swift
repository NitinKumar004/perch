import SwiftUI
import PerchCore

/// The typeface personality of a theme. A theme isn't just colour — its font
/// carries as much mood as its palette (mono reads "terminal", rounded reads
/// "soft/friendly", the system face reads "native"). One case → one `design`,
/// resolved at a given size/weight so the size hierarchy is preserved across
/// themes; only the character of the letters changes.
public enum Typeface: String, Sendable, Codable, CaseIterable, Identifiable {
    case system, rounded, monospaced

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system:      return "System"
        case .rounded:     return "Rounded"
        case .monospaced:  return "Mono"
        }
    }

    private var design: Font.Design {
        switch self {
        case .system:      return .default
        case .rounded:     return .rounded
        case .monospaced:  return .monospaced
        }
    }

    /// A font at `size`/`weight` in this typeface — the one place the HUD turns a
    /// theme's typeface into a concrete `Font`, so every label follows the theme.
    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

/// How the surface (pills, panel, banner) catches light. Solid is the original
/// flat look; frosted blurs what's behind (macOS vibrancy) for depth; glow adds
/// a soft accent-tinted halo. It's a per-theme identity choice AND a knob the
/// user can override on any theme.
public enum SurfaceMaterial: String, Sendable, Codable, CaseIterable, Identifiable {
    case solid, frosted, glow

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .solid:    return "Solid"
        case .frosted:  return "Frosted"
        case .glow:     return "Glow"
        }
    }
}

/// A theme's COMPLETE visual identity — colour, typeface, corner shape, and
/// material together. This is the single value the shell resolves everything
/// through, so switching themes transforms the whole HUD (not just its colours),
/// and adding a new theme is one `ThemeStyle`, not edits scattered across views.
///
/// `cornerScale` multiplies the views' base radii: `1.0` is the default rounding,
/// `< 1` reads sharper (terminal), `> 1` reads softer (squircle). Views ask for a
/// radius via `radius(_:)` rather than hard-coding one, so shape is themable in
/// one place.
public struct ThemeStyle: Sendable, Equatable {
    public var palette: Palette
    public var typeface: Typeface
    public var cornerScale: CGFloat
    public var material: SurfaceMaterial

    public init(palette: Palette, typeface: Typeface = .monospaced,
                cornerScale: CGFloat = 1.0, material: SurfaceMaterial = .solid) {
        self.palette = palette
        self.typeface = typeface
        self.cornerScale = cornerScale
        self.material = material
    }

    /// A font in the theme's typeface — sugar so views call `theme.font(11, .medium)`.
    public func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        typeface.font(size: size, weight: weight)
    }

    /// A base corner radius scaled to the theme's shape. Clamped so a theme can't
    /// produce a negative or absurd radius.
    public func radius(_ base: CGFloat) -> CGFloat {
        max(0, min(base * cornerScale, base * 3))
    }

    /// The same identity with a different accent — used by the user's accent
    /// override and by custom themes, without touching the rest of the palette.
    public func withAccent(_ accent: Color) -> ThemeStyle {
        var copy = self
        copy.palette.accent = accent
        return copy
    }

    /// The same identity with a different material — the user's material override.
    public func withMaterial(_ material: SurfaceMaterial) -> ThemeStyle {
        var copy = self
        copy.material = material
        return copy
    }

    /// The default identity — the look Perch has always shipped.
    public static let system = ThemeStyle(palette: .system, typeface: .monospaced,
                                          cornerScale: 1.0, material: .solid)

    /// The themed fill for a rounded card of `radius`: a translucent tint over a
    /// vibrancy blur for "frosted", a flat tint otherwise. The ONE place the
    /// material→pixels rule lives, so the live panel and the Settings preview can
    /// never drift (callers add their own stroke/glow, which differ by context).
    @ViewBuilder
    public func materialFill(radius: CGFloat) -> some View {
        ZStack {
            if material == .frosted {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(palette.surface.opacity(material == .frosted ? 0.5 : 0.92))
        }
    }
}

// MARK: - Environment plumbing

private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue: ThemeStyle = .system
}

public extension EnvironmentValues {
    /// The active theme identity. Views resolve colour (`theme.palette`), font
    /// (`theme.font`), shape (`theme.radius`) and material through this, so one
    /// change re-skins the whole HUD.
    var theme: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}
