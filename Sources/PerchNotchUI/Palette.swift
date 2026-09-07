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
    case system, midnight, terminal, solarized, nord, highContrast

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
        }
    }

    /// The palette this theme renders with.
    public var palette: Palette {
        switch self {
        case .system: return .system

        case .midnight:  // cool blues/violets on deep navy
            return Palette(
                neutral:  Color(red: 0.78, green: 0.82, blue: 0.95),
                good:     Color(red: 0.40, green: 0.80, blue: 0.74),
                warning:  Color(red: 0.95, green: 0.77, blue: 0.45),
                critical: Color(red: 0.98, green: 0.50, blue: 0.55),
                info:     Color(red: 0.52, green: 0.72, blue: 1.00),
                accent:   Color(red: 0.62, green: 0.60, blue: 0.98),
                surface:  Color(red: 0.05, green: 0.06, blue: 0.12),
                onSurface: Color(red: 0.86, green: 0.89, blue: 1.00))

        case .terminal:  // green-on-near-black, classic console
            return Palette(
                neutral:  Color(red: 0.72, green: 0.78, blue: 0.72),
                good:     Color(red: 0.36, green: 0.90, blue: 0.44),
                warning:  Color(red: 0.90, green: 0.82, blue: 0.36),
                critical: Color(red: 0.98, green: 0.44, blue: 0.40),
                info:     Color(red: 0.40, green: 0.85, blue: 0.80),
                accent:   Color(red: 0.36, green: 0.90, blue: 0.44),
                surface:  Color(red: 0.02, green: 0.04, blue: 0.02),
                onSurface: Color(red: 0.80, green: 0.94, blue: 0.80))

        case .solarized:  // the classic dev palette (dark base)
            return Palette(
                neutral:  Color(red: 0.58, green: 0.63, blue: 0.63),
                good:     Color(red: 0.52, green: 0.60, blue: 0.00),
                warning:  Color(red: 0.71, green: 0.54, blue: 0.00),
                critical: Color(red: 0.86, green: 0.20, blue: 0.18),
                info:     Color(red: 0.15, green: 0.55, blue: 0.82),
                accent:   Color(red: 0.83, green: 0.21, blue: 0.51),
                surface:  Color(red: 0.00, green: 0.17, blue: 0.21),
                onSurface: Color(red: 0.51, green: 0.58, blue: 0.59))

        case .nord:  // muted arctic tones
            return Palette(
                neutral:  Color(red: 0.85, green: 0.87, blue: 0.91),
                good:     Color(red: 0.64, green: 0.75, blue: 0.55),
                warning:  Color(red: 0.92, green: 0.80, blue: 0.55),
                critical: Color(red: 0.75, green: 0.38, blue: 0.42),
                info:     Color(red: 0.51, green: 0.63, blue: 0.76),
                accent:   Color(red: 0.53, green: 0.75, blue: 0.82),
                surface:  Color(red: 0.18, green: 0.20, blue: 0.25),
                onSurface: Color(red: 0.90, green: 0.91, blue: 0.94))

        case .highContrast:  // bold, accessible separations
            return Palette(
                neutral:  .white,
                good:     Color(red: 0.30, green: 1.00, blue: 0.40),
                warning:  Color(red: 1.00, green: 0.85, blue: 0.10),
                critical: Color(red: 1.00, green: 0.30, blue: 0.30),
                info:     Color(red: 0.40, green: 0.80, blue: 1.00),
                accent:   Color(red: 1.00, green: 1.00, blue: 0.30),
                surface:  .black,
                onSurface: .white)
        }
    }
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
