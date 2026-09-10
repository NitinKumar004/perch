import AppKit

/// Shared placement for Perch's auxiliary windows (Settings, Welcome, the GitHub
/// device-login window). Each is a reused, background-agent window, and without
/// this they misbehave for users with multiple monitors / Spaces / window-tabbing
/// on: opening on the wrong display, yanking the user to the Space the window was
/// first created on, or being absorbed as a tab into another app's window.
///
/// `prepareStandalone` makes a window open as its own standalone window on the
/// user's CURRENT screen and Space, every time it's shown. Call it right before
/// ordering the window front.
@MainActor
enum WindowPlacement {
    static func prepareStandalone(_ window: NSWindow) {
        window.tabbingMode = .disallowed                  // never merged into another window's tabs
        window.collectionBehavior = [.moveToActiveSpace]  // follow the user to their current Space
        if let screen = activeScreen() {
            window.setFrameOrigin(centeredOrigin(of: window.frame.size, in: screen.visibleFrame))
        }
    }

    /// The screen the user is currently on — the one under the cursor, falling
    /// back to the key/main screen.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// The origin that centres a window of `size` within a screen's `visibleFrame`.
    /// Pure, so the centring is unit-testable without a real screen.
    nonisolated static func centeredOrigin(of size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2)
    }
}
