import SwiftUI

/// A tiny inline trend chart: a line over a faint filled area, most-recent value
/// at the right with an emphasized endpoint. Scales to its frame; normalizes to
/// the 0–100 range so vitals gauges read consistently.
struct Sparkline: View {
    let points: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxV = 100.0            // vitals are percentages
            let minV = 0.0
            let range = max(1, maxV - minV)
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w

            let coords: [CGPoint] = points.enumerated().map { i, v in
                let x = CGFloat(i) * step
                let y = h - CGFloat((v - minV) / range) * h
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Faint area fill.
                Path { p in
                    guard let first = coords.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    coords.dropFirst().forEach { p.addLine(to: $0) }
                    if let last = coords.last {
                        p.addLine(to: CGPoint(x: last.x, y: h))
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
        }
    }
}
