import SwiftUI

/// A single line of text pinned to a fixed width. If the text fits, it's shown
/// statically; if it's longer, it gently scrolls back and forth (a marquee) so
/// the whole message is readable without the container ever growing — exactly
/// what a fixed-size notch banner needs for a long alert.
struct MarqueeText: View {
    let text: String
    let width: CGFloat
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            // No scrolling under Reduce Motion — so truncate with an ellipsis
            // rather than hard-clipping mid-glyph (a raw clip would leave the tail
            // permanently unreadable for exactly the users who can't scroll it).
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width, alignment: .leading)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()   // measure the text's natural width…
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { textWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in textWidth = newValue }
                })
                .offset(x: offset)
                .frame(width: width, alignment: .leading)
                .clipped()                       // …then clip to the fixed width
                .onAppear { restart(textWidth) }
                .onChange(of: textWidth) { _, tw in restart(tw) }
                .onChange(of: text) { _, _ in restart(textWidth) }
        }
    }

    /// (Re)start the scroll if — and only if — the text overflows the width.
    /// Only the non-Reduce-Motion branch of `body` calls this; under Reduce Motion
    /// the text is rendered by a separate truncating branch (tail ellipsis) and
    /// never scrolls — the one continuous animation in the app, so the one that
    /// most warrants suppression. (The `!reduceMotion` guard here is belt-and-
    /// suspenders; the caller already gates on it.)
    private func restart(_ measured: CGFloat) {
        let overflow = measured - width
        guard overflow > 4, !reduceMotion else { offset = 0; return }
        offset = 0
        withAnimation(
            .linear(duration: Double(overflow) / 22)     // speed scales with length
            .delay(0.9)                                   // read the start first
            .repeatForever(autoreverses: true)) {         // scroll out and back
            offset = -overflow
        }
    }
}
