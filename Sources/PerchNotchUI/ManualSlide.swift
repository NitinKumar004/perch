import SwiftUI

/// A row's title + subtitle that the user SLIDES by hand to read anything cut off
/// at the row's edge. Both lines live in ONE horizontal scroll view, so a sideways
/// swipe (two-finger trackpad / mouse wheel) moves them together in perfect sync —
/// nothing animates on its own, and a plain click still opens the row.
///
/// A `ScrollView` (not a `DragGesture`) is used deliberately: the row is a Button,
/// and on macOS a Button swallows click-drag gestures — but scroll events pass
/// straight through to an inner scroll view, so this actually responds. It's also
/// width-safe: the scroll view clips to the row's width, so a long title can't
/// force the panel wider.
struct ManualSlide: View {
    let title: String
    let titleFont: Font
    let titleColor: Color
    let subtitle: String?
    let subFont: Font
    let subColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(titleFont).foregroundStyle(titleColor)
                    .lineLimit(1).fixedSize()
                if let subtitle {
                    Text(subtitle)
                        .font(subFont).foregroundStyle(subColor)
                        .lineLimit(1).fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fold both lines into ONE VoiceOver element (the full, un-truncated text),
        // so the slide scroll view doesn't become an extra navigation stop.
        .accessibilityElement(children: .combine)
    }
}
