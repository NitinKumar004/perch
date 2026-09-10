import Testing
import CoreGraphics
@testable import PerchNotchUI

/// The sparkline value axis: percentages keep the fixed 0–100 gauge, large
/// series auto-scale, and — the regression that mattered — every plotted point
/// stays inside the frame so a big series can't overflow into a full-height
/// translucent strip down the panel.
@Suite struct SparklineTests {
    let box = CGSize(width: 64, height: 18)

    /// Percentages read against a fixed 0–100 axis: 0% sits at the bottom, 100%
    /// at the top, 50% in the middle — unchanged from before the fix.
    @Test func percentagesUseTheFixedGauge() {
        let pts = Sparkline.coordinates([0, 50, 100], in: box)
        #expect(pts.count == 3)
        #expect(abs(pts[0].y - 18) < 0.001)     // 0%   → bottom
        #expect(abs(pts[1].y - 9) < 0.001)      // 50%  → middle
        #expect(abs(pts[2].y - 0) < 0.001)      // 100% → top
    }

    /// A percentage series that never reaches 100 still reads against the full
    /// gauge (a steady ~40% shows as a low, calm line — not auto-amplified).
    @Test func lowPercentagesStayLow() {
        let pts = Sparkline.coordinates([30, 40, 35], in: box)
        // All in the lower ~two-thirds, none pinned to the top.
        #expect(pts.allSatisfy { $0.y > box.height * 0.5 })
    }

    /// Billions-scale tokens — the AI Usage series — auto-scale to their own peak
    /// AND every point stays within the frame (this is the overflow-band fix).
    @Test func largeSeriesStaysInsideTheFrame() {
        let pts = Sparkline.coordinates([4_800_000_000, 5_300_000_000, 3_600_000_000], in: box)
        #expect(pts.allSatisfy { $0.y >= 0 && $0.y <= box.height })   // never above/below the box
        #expect(abs(pts[1].y - 0) < 0.001)                            // the peak sits at the top
        #expect(pts[2].y > pts[0].y)                                  // 3.6B dips below 4.8B (a real trend)
    }

    /// Degenerate inputs never crash or escape the frame.
    @Test func edgeCasesAreSafe() {
        #expect(Sparkline.coordinates([], in: box).isEmpty)
        let flat = Sparkline.coordinates([2_000_000_000, 2_000_000_000], in: box)
        #expect(flat.allSatisfy { $0.y >= 0 && $0.y <= box.height })
        let single = Sparkline.coordinates([42], in: box)
        #expect(single.count == 1 && single[0].y >= 0 && single[0].y <= box.height)
    }

    /// The hero bar chart: bars are magnitude-relative (tallest = the peak day),
    /// every bar stays within the frame, and degenerate series stay safe.
    @Test func barHeightsAreRelativeAndInFrame() {
        let h: CGFloat = 46
        let bars = BarChart.heights([4_800_000_000, 5_300_000_000, 3_600_000_000], height: h)
        #expect(bars.count == 3)
        #expect(bars.allSatisfy { $0 >= 2 && $0 <= h })      // never escapes the box
        #expect(abs(bars[1] - h) < 0.001)                    // peak day = full height
        #expect(bars[2] < bars[0])                           // 3.6B shorter than 4.8B
    }

    @Test func barChartEdgeCasesAreSafe() {
        #expect(BarChart.heights([], height: 46).isEmpty)
        let zeros = BarChart.heights([0, 0, 0], height: 46)
        #expect(zeros == [2, 2, 2])                           // all-zero → thin floor bars
    }

    /// The hover tooltip is clamped inside the chart: over the first/last bar it
    /// never runs off an edge, and over a middle bar it centers on that bar.
    @Test func tooltipNeverOverflowsTheChart() {
        let width: CGFloat = 348, bubble: CGFloat = 96, spacing: CGFloat = 3, n = 14
        let first = BarChart.tooltipX(index: 0, count: n, spacing: spacing, width: width, bubbleWidth: bubble)
        let last = BarChart.tooltipX(index: n - 1, count: n, spacing: spacing, width: width, bubbleWidth: bubble)
        #expect(first >= 0)                                   // left edge: pinned in
        #expect(abs(first - 0) < 0.001)                       // ...to exactly 0
        #expect(last + bubble <= width + 0.001)               // right edge: fully inside
        #expect(abs((last + bubble) - width) < 0.001)         // ...flush to the right
        // A middle bar centers the bubble on it, still fully inside the frame.
        let mid = BarChart.tooltipX(index: 7, count: n, spacing: spacing, width: width, bubbleWidth: bubble)
        #expect(mid >= 0 && mid + bubble <= width)
    }
}
