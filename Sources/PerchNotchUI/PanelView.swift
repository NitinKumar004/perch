import SwiftUI
import PerchCore
import PerchModuleKit

/// Actions the panel footer can trigger, wired by the app. Keeping the controls
/// here means everything is reachable straight from the notch — no hunting for
/// the menu-bar icon.
public struct PanelActions: Sendable {
    public var onConnect: @MainActor () -> Void
    public var onSettings: @MainActor () -> Void
    public var onReload: @MainActor () -> Void
    public var onQuit: @MainActor () -> Void

    public init(onConnect: @escaping @MainActor () -> Void = {},
                onSettings: @escaping @MainActor () -> Void = {},
                onReload: @escaping @MainActor () -> Void = {},
                onQuit: @escaping @MainActor () -> Void = {}) {
        self.onConnect = onConnect
        self.onSettings = onSettings
        self.onReload = onReload
        self.onQuit = onQuit
    }
}

/// The drop-down detail card that appears below the notch when opened. It lists
/// each configured panel module as a labelled row — the module's name, its
/// pill, and an honest freshness note — and a footer of controls. This is the
/// "report" + control surface.
struct PanelView: View {
    let items: [PanelItem]
    let isConnected: Bool
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer(minLength: 12)
                    PillView(item.content)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                Divider().overlay(.white.opacity(0.06))
            }
            if items.isEmpty {
                Text("No panel modules configured")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 14)
            }

            footer
        }
        .padding(.vertical, 4)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.08)))
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isConnected {
                controlButton("Connect GitHub", system: "person.badge.key", tint: .accentColor, action: actions.onConnect)
            }
            controlButton("Settings", system: "gearshape", action: actions.onSettings)
            controlButton("Reload", system: "arrow.clockwise", action: actions.onReload)
            Spacer(minLength: 0)
            controlButton("Quit", system: "power", action: actions.onQuit)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func controlButton(_ title: String, system: String, tint: Color = .white,
                               action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(0.9))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
