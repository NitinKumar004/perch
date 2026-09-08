import AppKit
import SwiftUI

/// The panel's content view. The notch window is deliberately wide (so the pills
/// can flank the physical notch and stay centred), which means most of it floats
/// over the menu bar's app menus and menu-bar extras. `NSHostingView` claims
/// every click inside its bounds regardless of what SwiftUI draws there, so a
/// plain host would swallow those menu clicks. This container instead hit-tests
/// ONLY the frames SwiftUI reports as interactive (the pills, the banner, the
/// open panel) and returns nil everywhere else — so every other click falls
/// straight through to whatever is beneath (the menu bar).
final class PassThroughView: NSView {
    /// Interactive regions in this view's own (flipped, top-left) coordinates,
    /// pushed from SwiftUI as the pills/banner/panel change.
    var interactiveFrames: [CGRect] = []

    // Match SwiftUI's top-left origin so reported frames map without flipping.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates; bring it into ours.
        let local = convert(point, from: superview)
        guard interactiveFrames.contains(where: { $0.contains(local) }) else {
            return nil   // not on a pill/panel → let the menu bar have the click
        }
        return super.hitTest(point)
    }
}

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
    /// The pass-through content view — holds the live interactive frames used to
    /// decide, per cursor position, whether the window should catch clicks.
    private let container: PassThroughView
    /// Cursor monitors that flip `ignoresMouseEvents`: the global one sees moves
    /// while the window is transparent (event went to the app beneath), the local
    /// one sees moves while it's catching clicks (over a pill). Between them the
    /// toggle always tracks the cursor. Removed on deinit.
    // Set once on the main actor at init; only read back in deinit to remove.
    nonisolated(unsafe) private var globalMouseMonitor: Any?
    nonisolated(unsafe) private var localMouseMonitor: Any?

    // Generous zone on each side of the notch so a wide pill (e.g. a Combined
    // "CPU 32% · RAM 61% · ↓ 25 KB/s") never runs under the notch and clips.
    // Empty areas of the panel pass clicks through, so a wider zone is safe.
    private let pillZone: CGFloat = 400
    private let groupedWidth: CGFloat = 320
    private let panelDrop: CGFloat = 320
    /// The open panel card is a fixed 380pt wide (see PanelView). The window must
    /// be at least this wide in the grouped positions (.right/.below), or the card
    /// is wider than its own window and gets clipped on both edges. +16 leaves a
    /// little breathing room for the card's border/shadow.
    private let cardWidth: CGFloat = 380 + 16
    /// Space reserved on the RIGHT of the menu bar for the system extras (Wi-Fi,
    /// clock, Control Center…). macOS doesn't expose where those sit, so we keep a
    /// sensible margin and never let the flank window grow into it — that's what
    /// stops a wide pill or the alert banner from overlapping them.
    private let systemExtrasReserve: CGFloat = 340
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
        // Start transparent to the mouse — the window is wide and floats over the
        // menu bar, so by default every click must reach the menu bar beneath. We
        // flip this to `false` only while the cursor is actually over a pill/panel
        // (see updateClickThrough). `ignoresMouseEvents` is the ONLY thing that
        // makes a click reach the system menu bar under us — hitTest can't.
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true

        // A pass-through container that also tracks which sub-frames are the
        // pills/panel, so the cursor monitors know where clicks should land.
        container = PassThroughView(frame: NSRect(x: 0, y: 0, width: 600, height: 34))
        let root = NotchRootView(
            model: model, onActivate: onActivate, panelActions: panelActions,
            onInteractiveFrames: { [weak self] frames in
                self?.container.interactiveFrames = frames
                self?.updateClickThrough()   // frames changed → re-evaluate now
            })
        let hosting = NSHostingView(rootView: root)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        applyGeometry()
        installMouseMonitors()

        // Reposition on any display change.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // After sleep/wake or screen-unlock the cursor can be resting over a pill
        // with no `mouseMoved` to re-evaluate the toggle — which would leave the
        // window transparent and eat the first click. Resync the click-through
        // state on each of those wake events so the very first click lands right.
        for name: NSNotification.Name in [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(cursorMayHaveJumped), name: name, object: nil)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
    }

    /// A wake/unlock may have moved the cursor's relationship to the window with
    /// no `mouseMoved` — re-evaluate the click-through toggle from scratch.
    @objc private func cursorMayHaveJumped() { updateClickThrough() }

    /// Watch the cursor so the window catches clicks only while it's over a pill
    /// or the open panel, and is otherwise transparent to the mouse (letting the
    /// menu bar beneath receive the click).
    private func installMouseMonitors() {
        // Both fire on the main thread; run the update synchronously so the toggle
        // is set before any following mouse-down is delivered.
        // Fires while the window is transparent (the move went to the app beneath).
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }
        // Fires while the window is catching clicks (cursor over a pill), so we
        // notice the moment it leaves and can go transparent again.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateClickThrough() }
            return event
        }
    }

    /// Set `ignoresMouseEvents` from the live cursor position: opaque to the mouse
    /// only over an interactive frame, transparent everywhere else.
    private func updateClickThrough() {
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        // Into the (flipped) container's coordinates, matching the reported frames.
        let local = container.convert(windowPoint, from: nil)
        let overInteractive = container.interactiveFrames.contains { $0.contains(local) }
        // Only toggle on change — avoids churning the window server every move.
        if panel.ignoresMouseEvents == overInteractive {
            panel.ignoresMouseEvents = !overInteractive
        }
    }

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
        // The transient alert banner shows in-place in the pill row, so only the
        // panel grows the window.
        let height = model.isPanelOpen ? collapsedHeight + panelDrop : collapsedHeight

        let width: CGFloat
        let originX: CGFloat
        let originY: CGFloat
        switch position {
        case .flank:
            // Pills flank the physical notch, flush in the menu bar. The zone on
            // EACH side of the notch is capped to the free space before the system
            // extras on the right — so a wide pill or the alert banner is kept in
            // the empty part of the bar and never grows over the Wi-Fi/clock icons.
            // (Symmetric, so the notch gap stays centred on the physical notch; the
            // left side has even more room, so the right is the binding limit.)
            model.notchWidth = metrics.notchWidth
            let notchRightEdge = frameRect.midX + metrics.notchWidth / 2
            let rightFree = max(140, (frameRect.maxX - systemExtrasReserve) - notchRightEdge)
            let halfZone = min(pillZone, rightFree)
            width = min(frameRect.width, metrics.notchWidth + halfZone * 2)
            originX = frameRect.midX - width / 2
            originY = frameRect.maxY - height
        case .right:
            // Grouped just right of the notch — clear of the app menus (left).
            // Width must fit the open panel card (380pt), not just the compact
            // pills, or the card overflows this window and clips. Clamp so the
            // window never runs off the right screen edge.
            model.notchWidth = 0
            let rightStart = frameRect.midX + metrics.notchWidth / 2
            width = min(max(groupedWidth, cardWidth), frameRect.maxX - rightStart)
            originX = rightStart
            originY = frameRect.maxY - height
        case .below:
            // Grouped, centered, hanging just below the menu bar (non-notch).
            model.notchWidth = 0
            width = max(groupedWidth, cardWidth)
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
