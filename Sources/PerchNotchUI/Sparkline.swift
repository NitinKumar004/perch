import SwiftUI
import PerchCore

/// A thin completion bar — a filled portion over a faint track, capsule-capped.
/// Used to show a CI pipeline's progress (5/10 checks) at a glance, cleanly.
struct MiniBar: View {
    let value: Double   // 0…1
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(1, max(0, value)))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: max(3, geo.size.width * clamped))
            }
        }
    }
}

/// A full-width daily bar chart: one bar per value, heights relative to the
/// series peak, the most-recent bar emphasized and the rest dimmed. Used as a
/// section's "hero" chart (e.g. tokens per day) where a squeezed inline sparkline
/// would waste the row's width. Bars are magnitude-relative (normalized to the
/// series max), which is the right reading for "usage per day".
struct BarChart: View {
    let points: [Double]
    let color: Color
    /// Optional per-bar label (same order as `points`), e.g. a date — shown in the
    /// hover tooltip so a reader can tell which bar is which day.
    var labels: [String] = []
    @Environment(\.palette) private var palette
    @Environment(\.theme) private var theme
    @State private var hovered: Int?

    private static let bubbleWidth: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let spacing = barSpacing(count: points.count)
            let heights = Self.heights(points, height: geo.size.height)
            ZStack(alignment: .topLeading) {
                // The bars — clipped so a bar can never paint outside the frame.
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(heights.enumerated()), id: \.offset) { i, barHeight in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color.opacity(fill(for: i, count: heights.count)))
                            .frame(height: barHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { hovered = i } else if hovered == i { hovered = nil }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipped()

                // The hover tooltip — a solid bubble over the hovered bar, clamped
                // inside the chart so it never runs off an edge (drawn OUTSIDE the
                // clip so it can sit above the bars, not sliced by the frame).
                if let h = hovered, points.indices.contains(h) {
                    tooltip(for: h, in: geo.size, spacing: spacing)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }

    /// The hovered bar is full-strength, the most-recent bar bright, the rest dim.
    private func fill(for i: Int, count: Int) -> Double {
        if hovered == i { return 1 }
        return i == count - 1 ? 0.9 : 0.4
    }

    @ViewBuilder
    private func tooltip(for i: Int, in size: CGSize, spacing: CGFloat) -> some View {
        let x = Self.tooltipX(index: i, count: points.count, spacing: spacing,
                              width: size.width, bubbleWidth: Self.bubbleWidth)
        VStack(spacing: 1) {
            if i < labels.count {
                Text(labels[i])
                    .font(theme.font(10, .semibold))
                    .foregroundStyle(palette.ink(0.95))
            }
            Text(NumberFormat.compact(points[i]))
                .font(theme.font(9))
                .foregroundStyle(palette.ink(0.6))
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(width: Self.bubbleWidth)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(palette.ink(0.12)))
        )
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .offset(x: x, y: -6)          // float just above the bars
        .allowsHitTesting(false)      // never eat the hover it's reacting to
        .transition(.opacity)
    }

    /// A touch more air between few bars, tighter for a full two-week run.
    private func barSpacing(count: Int) -> CGFloat { count > 20 ? 2 : 3 }

    /// Left offset for the tooltip bubble over bar `index`, centered on the bar and
    /// clamped so `[x, x+bubbleWidth]` stays within `0…width` — the bubble can
    /// never overflow the chart's edges. Pure, so the clamping is unit-testable.
    nonisolated static func tooltipX(index: Int, count: Int, spacing: CGFloat,
                                     width: CGFloat, bubbleWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let cellW = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let center = CGFloat(index) * (cellW + spacing) + cellW / 2
        return min(max(0, center - bubbleWidth / 2), max(0, width - bubbleWidth))
    }

    /// Bar heights within `height`, normalized to the series peak. Pure (no
    /// SwiftUI) so it's unit-testable: every bar is `2…height`, the tallest is a
    /// non-empty series' max, and an all-zero/empty series is flat at the floor.
    nonisolated static func heights(_ points: [Double], height: CGFloat) -> [CGFloat] {
        guard !points.isEmpty else { return [] }
        let maxV = points.max() ?? 0
        guard maxV > 0 else { return points.map { _ in 2 } }   // all-zero → thin floor bars
        return points.map { v in
            let frac = min(1, max(0, v / maxV))
            return max(2, height * CGFloat(frac))
        }
    }
}

/// A tiny inline trend chart: a line over a faint filled area, most-recent value
/// at the right with an emphasized endpoint. Scales to its frame.
///
/// The value axis is `0…max(100, seriesMax)` (baseline `min(0, seriesMin)`): a
/// percentage series (CPU/RAM, always ≤ 100) reads against a fixed 0–100 gauge as
/// before, while a large-magnitude series (e.g. token counts in the billions)
/// auto-scales to its own peak instead of shooting far above the frame. The old
/// hardcoded 0–100 axis made a billions-scale series map to a `y` thousands of
/// points above the box; since SwiftUI doesn't clip by default, the area fill
/// became a giant translucent rectangle the panel clipped into a full-height
/// strip down the card. Data-aware bounds keep every point inside the frame, and
/// `.clipped()` is a structural backstop so no future series can overflow again.
struct Sparkline: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let coords = Self.coordinates(points, in: geo.size)
            ZStack {
                // Faint area fill.
                Path { p in
                    guard let first = coords.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    coords.dropFirst().forEach { p.addLine(to: $0) }
                    if let last = coords.last {
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    }
                    p.closeSubpath()
                }
                .fill(color.opacity(0.15))

                // The line.
                Path { p in
                    guard let first = coords.first else { return }
                    p.move(to: first)
                    coords.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                // Emphasized endpoint.
                if let last = coords.last {
                    Circle().fill(color).frame(width: 3, height: 3).position(last)
                }
            }
            .clipped()   // a series can never paint outside its own frame
        }
    }

    /// Map a value series to plotted points within `size`. Pure (no SwiftUI, no
    /// clock) so the axis behaviour is unit-testable. The axis spans
    /// `min(0, seriesMin) … max(100, seriesMax)` so percentages keep the fixed
    /// 0–100 gauge and large series auto-scale; every returned `y` is clamped to
    /// `0…height`, so the plot is always inside the frame.
    nonisolated static func coordinates(_ points: [Double], in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let maxV = max(100.0, points.max() ?? 100.0)
        let minV = min(0.0, points.min() ?? 0.0)
        let range = max(1, maxV - minV)
        let step = points.count > 1 ? size.width / CGFloat(points.count - 1) : size.width
        return points.enumerated().map { i, v in
            let x = CGFloat(i) * step
            let norm = min(1, max(0, (v - minV) / range))   // clamp into the frame
            let y = size.height - CGFloat(norm) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
