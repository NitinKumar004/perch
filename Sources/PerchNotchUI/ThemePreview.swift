import SwiftUI

/// A live, self-contained mini-Perch — a menu-bar pill + a dropdown card — drawn
/// in a given `ThemeStyle`. Used in Settings so the picker SHOWS each theme's
/// full identity (colour + typeface + corner shape + material), and so the "final
/// look" preview updates the instant you change accent/material. Pure: hand it a
/// style, it renders; no environment, no app state.
public struct ThemePreview: View {
    private let style: ThemeStyle
    private let name: String
    private let tagline: String
    private let compact: Bool

    public init(style: ThemeStyle, name: String, tagline: String, compact: Bool = false) {
        self.style = style
        self.name = name
        self.tagline = tagline
        self.compact = compact
    }

    private var p: Palette { style.palette }
    private var s: CGFloat { compact ? 0.85 : 1 }   // scale factor

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pillRow
            card
        }
        .background(Color.black.opacity(0.85))   // clean flat backdrop, no colour shade
        .clipShape(RoundedRectangle(cornerRadius: style.radius(14), style: .continuous))
    }

    /// The menu-bar strip with a mini combined pill.
    private var pillRow: some View {
        HStack(spacing: 5 * s) {
            Image(systemName: "pin.fill")
                .font(style.font(9 * s, .semibold)).foregroundStyle(p.warning)
            Text("CPU").font(style.font(9 * s, .medium)).foregroundStyle(p.good)
            Text("24%").font(style.font(9 * s, .medium)).foregroundStyle(p.onSurface)
            Text("·").foregroundStyle(p.onSurface.opacity(0.35))
            Text("RAM 76%").font(style.font(9 * s, .medium)).foregroundStyle(p.warning)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * s).padding(.vertical, 6 * s)
        .background(Color.black.opacity(0.28))
    }

    /// The dropdown card — name, tagline, swatches — on the theme's material.
    private var card: some View {
        let r = style.radius(11)
        return VStack(alignment: .leading, spacing: 4 * s) {
            Text(name).font(style.font(compact ? 13 : 15, .bold)).foregroundStyle(p.onSurface)
            Text(tagline).font(style.font(compact ? 9 : 11)).foregroundStyle(p.onSurface.opacity(0.55))
            HStack(spacing: 4) {
                ForEach(Array([p.good, p.warning, p.critical, p.info, p.accent].enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 10 * s, height: 10 * s)
                }
            }
            .padding(.top, 2)
        }
        .padding(compact ? 11 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface(r))
        .padding(compact ? 8 : 10)
    }

    /// Material-aware card fill: frosted blurs the desktop behind it, glow adds an
    /// accent halo, solid is a flat tint.
    @ViewBuilder private func cardSurface(_ r: CGFloat) -> some View {
        style.materialFill(radius: r)   // shared with the live panel — no drift
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                .strokeBorder(p.onSurface.opacity(0.1), lineWidth: 1))
            .shadow(color: style.material == .glow ? p.accent.opacity(0.5) : .clear,
                    radius: style.material == .glow ? 14 : 0)
    }
}
