import AppKit
import SwiftUI
import PerchConfig

/// Hosts the SwiftUI settings form in a normal, focusable window (unlike the
/// notch panel, this one is meant to be clicked into). Kept as a single reused
/// window so repeated "Settings…" clicks bring the same one forward.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    /// Show the settings window for `config`; `onSave` receives the edited
    /// config to persist and apply.
    func show(config: LayoutConfig, onSave: @escaping (LayoutConfig) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(config: config) { [weak self] edited in
            onSave(edited)
            self?.window?.close()
        }

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Perch Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
