import SwiftUI
import PerchCore

/// The single source of truth mapping the HUD's semantic `Tint` language to
/// concrete colours. One `Palette` is one theme: the shell resolves *every*
/// colour through the active palette, so swapping the palette re-skins the whole
/// HUD without any module or view knowing a colour changed.
///
/// Modules still speak only in `Tint` (`.good`, `.critical`); this is the one
/// place meaning becomes pixels — which is exactly what makes theming possible.
public struct Palette: Sendable, Equatable {
    // Status tints — what a module's `Tint` resolves to.
    public var neutral: Color
    public var good: Color
    public var warning: Color
    public var critical: Color
    public var info: Color
    public var accent: Color
    // Chrome roles — the surface a HUD sits on and the ink on top of it, so a
    // theme recolours the whole panel (background + text), not only the dots.
    // A light theme is impossible without these.
    public var surface: Color    // the panel's background
    public var onSurface: Color  // primary text and icons on the surface (pills too)

    public init(neutral: Color, good: Color, warning: Color,
                critical: Color, info: Color, accent: Color,
                surface: Color, onSurface: Color) {
        self.neutral = neutral
        self.good = good
        self.warning = warning
        self.critical = critical
        self.info = info
        self.accent = accent
        self.surface = surface
        self.onSurface = onSurface
    }

    /// Resolve a semantic tint to its colour in this palette.
    public func color(for tint: Tint) -> Color {
        switch tint {
        case .neutral:  return neutral
        case .good:     return good
        case .warning:  return warning
        case .critical: return critical
        case .info:     return info
        case .accent:   return accent
        }
    }

    /// Ink on the surface at a given strength — the one place the panel's
    /// text/divider/icon opacities come from, so they follow the theme.
    public func ink(_ opacity: Double) -> Color { onSurface.opacity(opacity) }
}

public extension Palette {
    /// The default look — the palette Perch has always shipped. Kept as the
    /// baseline every other theme is a variation on. `surface`/`onSurface`
    /// preserve the original panel look (near-black surface, white ink).
    static let system = Palette(
        neutral:  Color(white: 0.9),
        good:     Color(red: 0.25, green: 0.73, blue: 0.31),
        warning:  Color(red: 0.89, green: 0.70, blue: 0.25),
        critical: Color(red: 1.00, green: 0.42, blue: 0.37),
        info:     Color(red: 0.42, green: 0.71, blue: 1.00),
        accent:   Color(red: 0.72, green: 0.63, blue: 1.00),
        surface:  Color(white: 0.02),
        onSurface: .white)
}

/// A named colour theme the user can pick. Each case is one `Palette`. Stored in
/// config by its `rawValue`, so the id is stable and round-trips cleanly (a
/// `Palette`'s `Color`s don't).
public enum Theme: String, Sendable, CaseIterable, Identifiable {
    case system, midnight, terminal, solarized, nord, highContrast, aurora

    public var id: String { rawValue }

    /// The name shown in the picker.
    public var label: String {
        switch self {
        case .system:       return "System"
        case .midnight:     return "Midnight"
        case .terminal:     return "Terminal"
        case .solarized:    return "Solarized"
        case .nord:         return "Nord"
        case .highContrast: return "High Contrast"
        case .aurora:       return "Aurora"
        }
    }

    /// A one-line personality shown under the name — themes have a voice.
    public var tagline: String {
        switch self {
        case .system:       return "the native look"
        case .midnight:     return "deep, soft, glowing"
        case .terminal:     return "green phosphor, sharp"
        case .solarized:    return "warm, classic, calm"
        case .nord:         return "arctic, muted, frosted"
        case .highContrast: return "bold and legible"
        case .aurora:       return "adapts to your wallpaper"
        }
    }

    /// The COMPLETE identity this theme renders with — colour + typeface + shape
    /// + material. A theme is a variation across all four, not just colour.
    public var style: ThemeStyle {
        switch self {
        case .system:
            return ThemeStyle(palette: .system, typeface: .monospaced,
                              cornerScale: 1.0, material: .solid)

        case .midnight:  // cool blues/violets on deep navy — rounded & glowing
            return ThemeStyle(palette: Palette(
                neutral:  Color(red: 0.78, green: 0.82, blue: 0.95),
                good:     Color(red: 0.37, green: 0.88, blue: 0.75),
                warning:  Color(red: 0.97, green: 0.73, blue: 0.35),
                critical: Color(red: 1.00, green: 0.48, blue: 0.60),
                info:     Color(red: 0.49, green: 0.62, blue: 1.00),
                accent:   Color(red: 0.49, green: 0.62, blue: 1.00),
                surface:  Color(red: 0.05, green: 0.06, blue: 0.16),
                onSurface: Color(red: 0.92, green: 0.94, blue: 1.00)),
                typeface: .rounded, cornerScale: 1.4, material: .glow)

        case .terminal:  // green-on-near-black console — mono & sharp-cornered
            return ThemeStyle(palette: Palette(
                neutral:  Color(red: 0.44, green: 0.68, blue: 0.44),
                good:     Color(red: 0.22, green: 1.00, blue: 0.42),
                warning:  Color(red: 0.84, green: 1.00, blue: 0.22),
                critical: Color(red: 1.00, green: 0.36, blue: 0.36),
                info:     Color(red: 0.30, green: 0.95, blue: 0.85),
                accent:   Color(red: 0.22, green: 1.00, blue: 0.42),
                surface:  Color(red: 0.00, green: 0.03, blue: 0.00),
                onSurface: Color(red: 0.72, green: 1.00, blue: 0.72)),
                typeface: .monospaced, cornerScale: 0.25, material: .solid)

        case .solarized:  // the classic dev palette (dark base) — mono, calm
            return ThemeStyle(palette: Palette(
                neutral:  Color(red: 0.58, green: 0.63, blue: 0.63),
                good:     Color(red: 0.52, green: 0.60, blue: 0.00),
                warning:  Color(red: 0.71, green: 0.54, blue: 0.00),
                critical: Color(red: 0.86, green: 0.20, blue: 0.18),
                info:     Color(red: 0.15, green: 0.55, blue: 0.82),
                accent:   Color(red: 0.15, green: 0.55, blue: 0.82),
                surface:  Color(red: 0.00, green: 0.17, blue: 0.21),
                onSurface: Color(red: 0.93, green: 0.91, blue: 0.84)),
                typeface: .monospaced, cornerScale: 0.85, material: .solid)

        case .nord:  // muted arctic tones — rounded & frosted
            return ThemeStyle(palette: Palette(
                neutral:  Color(red: 0.85, green: 0.87, blue: 0.91),
                good:     Color(red: 0.64, green: 0.75, blue: 0.55),
                warning:  Color(red: 0.92, green: 0.80, blue: 0.55),
                critical: Color(red: 0.75, green: 0.38, blue: 0.42),
                info:     Color(red: 0.53, green: 0.75, blue: 0.82),
                accent:   Color(red: 0.53, green: 0.75, blue: 0.82),
                surface:  Color(red: 0.18, green: 0.20, blue: 0.25),
                onSurface: Color(red: 0.93, green: 0.94, blue: 0.96)),
                typeface: .rounded, cornerScale: 1.25, material: .frosted)

        case .highContrast:  // bold, accessible separations — system face, crisp
            return ThemeStyle(palette: Palette(
                neutral:  .white,
                good:     Color(red: 0.30, green: 1.00, blue: 0.40),
                warning:  Color(red: 1.00, green: 0.85, blue: 0.10),
                critical: Color(red: 1.00, green: 0.30, blue: 0.30),
                info:     Color(red: 0.40, green: 0.80, blue: 1.00),
                accent:   Color(red: 1.00, green: 1.00, blue: 0.30),
                surface:  .black,
                onSurface: .white),
                typeface: .system, cornerScale: 0.6, material: .solid)

        case .aurora:  // wallpaper-adaptive; ships a vivid default — rounded, frosted
            return ThemeStyle(palette: Palette(
                neutral:  Color(red: 0.85, green: 0.80, blue: 0.92),
                good:     Color(red: 0.49, green: 0.91, blue: 0.77),
                warning:  Color(red: 0.99, green: 0.83, blue: 0.30),
                critical: Color(red: 0.98, green: 0.44, blue: 0.52),
                info:     Color(red: 0.66, green: 0.72, blue: 1.00),
                accent:   Color(red: 0.94, green: 0.67, blue: 0.99),
                surface:  Color(red: 0.12, green: 0.06, blue: 0.20),
                onSurface: Color(red: 0.99, green: 0.96, blue: 1.00)),
                typeface: .rounded, cornerScale: 1.5, material: .frosted)
        }
    }

    /// Back-compat sugar: the theme's colours. Everything colour-only still reads
    /// `.palette`; the richer views read the full `.style`.
    public var palette: Palette { style.palette }
}

// MARK: - Environment plumbing

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .system
}

public extension EnvironmentValues {
    /// The active palette. Views resolve `Tint → Color` through this, so a theme
    /// change flows down the view tree and re-skins everything automatically.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
