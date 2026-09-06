import AppKit
import SwiftUI

/// The first-launch greeting. Shown once, when no config file exists yet, so a
/// brand-new user understands what Perch is and how to make it theirs — connect
/// GitHub, open Settings, done. Never shown again after the config is written.
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?

    func show(onConnect: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = WelcomeView(
            onConnect: onConnect,
            onOpenSettings: { [weak self] in self?.window?.close(); onOpenSettings() },
            onDone: { [weak self] in self?.window?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Perch"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A calm, one-screen introduction: what Perch is, the three signals it starts
/// with locally, and the two buttons that take it further.
struct WelcomeView: View {
    let onConnect: () -> Void
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bird.fill").font(.system(size: 26)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Perch").font(.system(size: 22, weight: .semibold))
                    Text("A calm “is everything okay?” in your notch.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                row("cpu", "Watching your Mac already",
                    "CPU, memory and a clock are live in the notch right now — no setup.")
                row("arrow.triangle.pull", "Add your GitHub",
                    "Connect once to watch builds and pull requests — see CI progress at a glance.")
                row("slider.horizontal.3", "Make it yours",
                    "In Settings, pick exactly what each slot shows. Nothing is fixed.")
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: onConnect) {
                    Label("Connect GitHub", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)
                Button("Open Settings", action: onOpenSettings)
                Spacer()
                Button("Start using Perch", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
