import AppKit
import SwiftUI

/// Owns the borderless, non-activating panel that floats at the notch.
///
/// The window never steals focus (`.nonactivatingPanel`), floats above normal
/// windows (`.statusBar` level), survives Space switches, and — in this first
/// phase — ignores mouse events, so it is purely a heads-up display.
@MainActor
public final class NotchWindowController {
    private let panel: NSPanel

    public init(model: NotchViewModel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let metrics = screen.map(NotchGeometry.metrics(for:))
            ?? NotchMetrics(hasNotch: false, notchWidth: 0, notchHeight: 24,
                            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

        let pillZone: CGFloat = 220
        let width = metrics.notchWidth + pillZone * 2
        let height = max(metrics.notchHeight, 32)
        let originX = metrics.screenFrame.midX - width / 2
        let originY = metrics.screenFrame.maxY - height
        let contentRect = NSRect(x: originX, y: originY, width: width, height: height)

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
        panel.ignoresMouseEvents = true // phase 1: display-only

        let root = NotchRootView(model: model, notchWidth: metrics.notchWidth)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: contentRect.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hosting)
    }

    public func show() { panel.orderFrontRegardless() }
    public func hide() { panel.orderOut(nil) }
}
