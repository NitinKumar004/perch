import SwiftUI
import PerchCore

/// The transient alert shown IN the pill row. Deliberately styled EXACTLY like a
/// pill — the native, borderless menu-bar look (icon + monospaced text, no box)
/// — so nothing about the bar's shape changes; only the message arrives in place.
/// A long message scrolls (marquee) within a fixed width rather than growing.
/// Theme-aware; tapping opens the detail panel.
struct BannerView: View {
    private let banner: BannerAlert
    private let onTap: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.theme) private var theme

    /// The scrolling text area width — the element stays this size in the bar
    /// regardless of message length; longer text marquees inside it. One source of
    /// truth (shared with the dwell math) so the two can't drift.
    private let textWidth = CGFloat(MarqueeTiming.bannerSlotWidth)

    init(_ banner: BannerAlert, onTap: @escaping () -> Void) {
        self.banner = banner
        self.onTap = onTap
    }

    var body: some View {
        let accent = palette.color(for: banner.tint)
        let text = banner.body.isEmpty ? banner.title : "\(banner.title) · \(banner.body)"
        // Same structure as PillView: a fixed icon box + text, no background.
        return HStack(spacing: 5) {
            Image(systemName: banner.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .imageScale(.small)
                .frame(width: 13, height: 13)
                .clipped()
                .foregroundStyle(accent)
            MarqueeText(text: text, width: textWidth,
                        font: theme.font(11, .medium),
                        color: accent)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .help(text)
    }
}
