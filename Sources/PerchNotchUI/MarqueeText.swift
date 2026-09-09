import SwiftUI

/// One place for the marquee's timing, shared by the animation (`MarqueeText`) and
/// the banner's dwell (`BannerPresenter`) — so the banner stays on screen exactly
/// long enough to reveal the whole message once, instead of two numbers guessing
/// against each other.
public enum MarqueeTiming {
    /// Hold the start still before scrolling, so the beginning is read first.
    public static let startHold: Double = 0.5
    /// Linger on the end before reversing, so the tail is read too.
    public static let endPause: Double = 0.9
    /// Scroll speed (points per second) — brisk but readable.
    public static let pointsPerSecond: Double = 40
    /// The banner's fixed text slot and a per-character width estimate, so the
    /// presenter can turn a message length into an overflow in points. The width is
    /// rounded UP on purpose: 4 of the 7 themes render the banner in a proportional
    /// face at medium weight (not the monospaced ~6.7pt), so a generous estimate
    /// keeps the dwell on the safe side — it can only over-reveal, never cut short.
    static let bannerSlotWidth: Double = 230
    static let approxCharWidth: Double = 7.6

    /// Seconds to reveal text that overflows its slot by `overflow` points, once:
    /// hold + scroll + end pause. No overflow → no scroll → 0.
    public static func revealSeconds(overflow: Double) -> Double {
        guard overflow > 0 else { return 0 }
        return startHold + overflow / pointsPerSecond + endPause
    }

    /// The banner's reveal time from a message length, using the fixed slot width.
    public static func bannerRevealSeconds(textLength: Int) -> Double {
        revealSeconds(overflow: Double(max(0, textLength)) * approxCharWidth - bannerSlotWidth)
    }
}

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
    @State private var scrollTask: Task<Void, Never>?
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
                .onDisappear { scrollTask?.cancel() }
        }
    }

    /// (Re)start the scroll if — and only if — the text overflows the width.
    ///
    /// Driven by a hand-rolled loop (not `.repeatForever(autoreverses:)`) so the
    /// end genuinely HOLDS for `endPause` before reversing — `repeatForever` can't
    /// express a mid-cycle pause, so the tail would flash for a single frame and
    /// recede, making `endPause` a lie the banner's dwell math relies on. Each leg:
    /// hold the start, scroll to the end, hold the end, scroll back.
    private func restart(_ measured: CGFloat) {
        scrollTask?.cancel()
        let overflow = measured - width
        guard overflow > 4, !reduceMotion else { offset = 0; return }
        offset = 0
        let scroll = Double(overflow) / MarqueeTiming.pointsPerSecond
        scrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(MarqueeTiming.startHold))   // read the start
                if Task.isCancelled { return }
                withAnimation(.linear(duration: scroll)) { offset = -overflow }
                try? await Task.sleep(for: .seconds(scroll + MarqueeTiming.endPause))  // scroll + linger on the end
                if Task.isCancelled { return }
                withAnimation(.linear(duration: scroll)) { offset = 0 }
                try? await Task.sleep(for: .seconds(scroll))
            }
        }
    }
}
