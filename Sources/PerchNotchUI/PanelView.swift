import SwiftUI
import AppKit
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
            // Rows scroll if they exceed the panel height, so a rich panel (many
            // modules / a long PR list) never gets clipped.
            ScrollView {
                VStack(spacing: 0) {
                    rows
                }
            }
            .frame(maxHeight: 300)

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

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 0) {
                    // Header: module name (+ what it's watching) + its pill.
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 12)
                        PillView(item.content)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, item.detail.isEmpty ? 9 : 4)

                    // Detail rows (clickable when they carry a URL).
                    ForEach(item.detail) { row in
                        detailRow(row)
                    }
                }
                Divider().overlay(.white.opacity(0.06))
            }
            if items.isEmpty {
                Text("No panel modules configured")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 14)
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ row: DetailRow) -> some View {
        let content = HStack(spacing: 9) {
            if let symbol = row.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(tintColor(row.tint))
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let points = row.sparkline, points.count > 1 {
                Sparkline(points: points, color: tintColor(row.tint))
                    .frame(width: 64, height: 18)
            }
            if row.url != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        if let urlString = row.url, let url = URL(string: urlString) {
            Button { NSWorkspace.shared.open(url) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func tintColor(_ tint: Tint) -> Color {
        switch tint {
        case .neutral:  return Color(white: 0.85)
        case .good:     return Color(red: 0.25, green: 0.73, blue: 0.31)
        case .warning:  return Color(red: 0.89, green: 0.70, blue: 0.25)
        case .critical: return Color(red: 1.00, green: 0.42, blue: 0.37)
        case .info:     return Color(red: 0.42, green: 0.71, blue: 1.00)
        case .accent:   return Color(red: 0.72, green: 0.63, blue: 1.00)
        }
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
