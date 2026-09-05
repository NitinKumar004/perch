import AppKit

/// Measured facts about a screen's notch, or the absence of one.
public struct NotchMetrics: Sendable, Equatable {
    public let hasNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let screenFrame: CGRect
}

/// Resolves the notch geometry from AppKit so the window can be placed exactly
/// around it — and degrades cleanly to a floating pill on non-notch Macs.
public enum NotchGeometry {
    public static func metrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        // A positive top safe-area inset plus both auxiliary side areas means a
        // real hardware notch. `notchWidth` is the gap between the side areas.
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = frame.width - left.width - right.width
            return NotchMetrics(
                hasNotch: true,
                notchWidth: max(0, notchWidth),
                notchHeight: topInset,
                screenFrame: frame
            )
        }

        // No notch: caller will render a floating pill under the menu bar.
        return NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 24, screenFrame: frame)
    }
}
