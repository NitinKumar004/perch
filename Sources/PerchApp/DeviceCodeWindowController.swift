import AppKit
import SwiftUI
import Observation

/// The GitHub device-login helper window. The device flow gives the user a code
/// they must type at github.com/login/device — but a menu-bar agent has nowhere
/// obvious to show it. This surfaces the code big and clear, copies it, opens the
/// page, and flips to "Connected" when the handshake completes.
@MainActor
final class DeviceCodeWindowController {
    private var window: NSWindow?
    private let state = DeviceCodeState()

    /// Present the code (auto-copied) and the verification URL.
    func show(code: String, verificationUri: String) {
        state.code = code
        state.uri = verificationUri
        state.status = .waiting
        copyCode()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = DeviceCodeView(state: state, onCopy: { [weak self] in self?.copyCode() },
                                  onOpen: { [weak self] in self?.openPage() })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Connect to GitHub"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func markConnected() {
        state.status = .connected
        // Leave the success on screen briefly, then dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in self?.window?.close() }
    }

    func markFailed() { state.status = .failed }
    func close() { window?.close() }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.code, forType: .string)
    }
    private func openPage() {
        if let url = URL(string: state.uri) { NSWorkspace.shared.open(url) }
    }
}

@MainActor
@Observable
final class DeviceCodeState {
    enum Status { case waiting, connected, failed }
    var code = ""
    var uri = ""
    var status: Status = .waiting
}

/// The card: the code, a copy + open action, and a live status.
struct DeviceCodeView: View {
    let state: DeviceCodeState
    let onCopy: () -> Void
    let onOpen: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "person.badge.key.fill").font(.system(size: 20)).foregroundStyle(.tint)
                Text("Connect Perch to GitHub").font(.system(size: 17, weight: .semibold))
            }

            VStack(spacing: 6) {
                Text("Enter this code at github.com")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(state.code.isEmpty ? "········" : state.code)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .textSelection(.enabled)
                Text(copied ? "Copied to clipboard ✓" : "Copied to your clipboard")
                    .font(.system(size: 11)).foregroundStyle(copied ? .green : .secondary)
            }
            .padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))

            HStack(spacing: 10) {
                Button {
                    onCopy(); copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Label("Copy code", systemImage: "doc.on.doc") }
                Button { onOpen() } label: { Label("Open GitHub", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.borderedProminent)
            }

            statusLine
        }
        .padding(24)
        .frame(width: 380)
    }

    @ViewBuilder private var statusLine: some View {
        switch state.status {
        case .waiting:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to authorize on GitHub…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .connected:
            Label("Connected — you're all set.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
        case .failed:
            Label("Couldn't connect. Close and try again.", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundStyle(.orange)
        }
    }
}
