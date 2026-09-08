import SwiftUI

/// The ONE place the stored theme choices become a live `ThemeStyle`: pick the
/// base theme, then layer the user's overrides (a personal accent colour, a
/// material) on top. Both the running HUD (AppDelegate) and the Settings live
/// preview resolve through this, so what you see in the picker is exactly what
/// you get — no second code path that could drift.
///
/// Pure and primitive-typed (ids + hex strings, not config types) so it's
/// trivially testable and free of any layer dependency.
public enum ThemeResolver {
    /// Resolve a final style from the stored choices. Unknown/blank overrides are
    /// ignored (fall back to the base theme's own value), never crash.
    public static func resolve(themeID: String, accentHex: String?,
                               material: String?) -> ThemeStyle {
        var style = (Theme(rawValue: themeID) ?? .system).style
        if let material, !material.isEmpty, let m = SurfaceMaterial(rawValue: material) {
            style = style.withMaterial(m)
        }
        if let accentHex, !accentHex.isEmpty, let color = Color(hex: accentHex) {
            style = style.withAccent(color)
        }
        return style
    }
}

public extension Color {
    /// Parse `#RRGGBB` / `RRGGBB` (and `#RGB`) into a Color, or nil if malformed —
    /// so a bad stored/pasted value falls back to the theme's colour, never crashes.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue:  Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}
