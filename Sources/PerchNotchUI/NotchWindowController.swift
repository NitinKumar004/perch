import AppKit
import SwiftUI

/// Owns the borderless, non-activating panel that floats at the notch.
///
/// The window never steals focus (`.nonactivatingPanel`), floats above normal
/// windows (`.statusBar` level), and survives Space switches. Its pills are
/// clickable; the transparent notch gap passes clicks through. When the panel
/// opens the window grows downward — and shrinks back when it closes — so a tall
/// transparent window never sits over the desktop swallowing clicks while idle.
@MainActor
public final class NotchWindowController {
    private let panel: NSPanel
    private let collapsedHeight: CGFloat
    private let expandedHeight: CGFloat
    private let topEdgeY: CGFloat
    private let frameX: CGFloat
    private let frameWidth: CGFloat

    /// - Parameter onActivate: called when the user clicks a pill — used to
    ///   open/close the panel or start the GitHub connect flow.
    public init(model: NotchViewModel, onActivate: @escaping () -> Void = {}) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let metrics = screen.map(NotchGeometry.metrics(for:))
            ?? NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 24,
                            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

        let pillZone: CGFloat = 220
        frameWidth = metrics.notchWidth + pillZone * 2
        collapsedHeight = max(metrics.notchHeight, 32)
        expandedHeight = collapsedHeight + 320   // room for the drop-down panel
        frameX = metrics.screenFrame.midX - frameWidth / 2
        topEdgeY = metrics.screenFrame.maxY      // pin the top to the screen top

        let contentRect = NSRect(x: frameX, y: topEdgeY - collapsedHeight,
                                 width: frameWidth, height: collapsedHeight)

        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let root = NotchRootView(model: model, notchWidth: metrics.notchWidth, onActivate: onActivate)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentView?.bounds ?? contentRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
    }

    public func show() { panel.orderFrontRegardless() }
    public func hide() { panel.orderOut(nil) }

    /// Grow/shrink the window as the panel opens/closes, keeping the top edge
    /// pinned to the notch so the pills never move.
    public func setPanelOpen(_ open: Bool) {
        let height = open ? expandedHeight : collapsedHeight
        let frame = NSRect(x: frameX, y: topEdgeY - height, width: frameWidth, height: height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().setFrame(frame, display: true)
        }
    }
}
