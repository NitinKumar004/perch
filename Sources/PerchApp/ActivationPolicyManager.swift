import AppKit

/// Coordinates the app's activation policy across the several normal windows a
/// background (`.accessory`) agent shows — Settings, the GitHub device-code
/// window, the first-run Welcome window.
///
/// A `.accessory` (LSUIElement) app can't be foregrounded, so `NSApp.activate`
/// alone hands focus to some *other* regular app instead of showing our window in
/// place. Each such window therefore promotes the app to `.regular` while it's
/// open. But the app must only drop back to `.accessory` once the LAST of these
/// windows closes — otherwise closing one (e.g. Settings) would background another
/// that's still open mid-flow (e.g. the device-code window during GitHub connect).
/// This tracks the open windows by identity and reverts only when none remain.
@MainActor
final class ActivationPolicyManager {
    private var openWindows: Set<ObjectIdentifier> = []
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// Show `window` as a real foreground window: promote to `.regular` so it
    /// takes focus in place, bring it to front, activate, and arrange to drop back
    /// to `.accessory` once this and every other tracked window has closed. Safe to
    /// call again for an already-open (reused) window — it won't double-count.
    func present(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        openWindows.insert(id)
        if observers[id] == nil {
            observers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissed(id) }
            }
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissed(_ id: ObjectIdentifier) {
        openWindows.remove(id)
        if let observer = observers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        // Only return to a background agent once no foreground window remains.
        if openWindows.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
