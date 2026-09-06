import AppKit
import SwiftUI

/// Owns the borderless, non-activating panel that floats at the notch.
///
/// The window never steals focus (`.nonactivatingPanel`), floats above normal
/// windows (`.statusBar` level), and survives Space switches. Its pills are
/// clickable; the transparent notch gap passes clicks through. When the panel
/// opens the window grows downward — and shrinks back when it closes.
///
/// Geometry is recomputed whenever the display arrangement changes (plug/unplug
/// a monitor, resolution change, lid open/close), and the HUD always binds to
/// the screen that actually has the notch — falling back to a floating pill on
/// non-notch Macs.
@MainActor
public final class NotchWindowController {
    private let panel: NSPanel
    private let model: NotchViewModel

    private let pillZone: CGFloat = 220
    private let groupedWidth: CGFloat = 280
    private let panelDrop: CGFloat = 320
    private var position: HUDPosition = .flank

    public init(model: NotchViewModel,
                onActivate: @escaping () -> Void = {},
                panelActions: PanelActions = PanelActions()) {
        self.model = model

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 34),
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

        let root = NotchRootView(model: model, onActivate: onActivate, panelActions: panelActions)
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        applyGeometry()

        // Reposition on any display change.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    public func show() { panel.orderFrontRegardless() }
    public func hide() { panel.orderOut(nil) }

    /// Grow/shrink the window as the panel opens/closes, keeping the top edge
    /// pinned to the notch. When open, the panel becomes key so its footer
    /// buttons receive clicks; when closed it resigns so it never steals focus.
    public func setPanelOpen(_ open: Bool) {
        applyGeometry(animated: true)
        if open { panel.makeKeyAndOrderFront(nil) } else { panel.resignKey() }
    }

    @objc private func screensChanged() { applyGeometry(animated: false) }

    /// Change where the HUD sits, and re-lay it out.
    public func setPosition(_ position: HUDPosition) {
        self.position = position
        model.hudPosition = position
        applyGeometry(animated: false)
    }

    /// The screen with a real hardware notch, or the main screen as a fallback.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { NotchGeometry.metrics(for: $0).hasNotch } ?? NSScreen.main
    }

    /// Recompute the panel frame + notch gap for the current display and apply.
    private func applyGeometry(animated: Bool = false) {
        guard let screen = notchScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        let frameRect = metrics.screenFrame
        let collapsedHeight = max(metrics.notchHeight, 32)
        let height = model.isPanelOpen ? collapsedHeight + panelDrop : collapsedHeight

        let width: CGFloat
        let originX: CGFloat
        let originY: CGFloat
        switch position {
        case .flank:
            // Pills flank the physical notch, flush in the menu bar.
            model.notchWidth = metrics.notchWidth
            width = metrics.notchWidth + pillZone * 2
            originX = frameRect.midX - width / 2
            originY = frameRect.maxY - height
        case .right:
            // Grouped just right of the notch — clear of the app menus (left).
            model.notchWidth = 0
            width = groupedWidth
            originX = frameRect.midX + metrics.notchWidth / 2
            originY = frameRect.maxY - height
        case .below:
            // Grouped, centered, hanging just below the menu bar (non-notch).
            model.notchWidth = 0
            width = groupedWidth
            originX = frameRect.midX - width / 2
            originY = frameRect.maxY - height - metrics.notchHeight
        }
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
