import SwiftUI
import PerchCore
import PerchModuleKit

/// Renders one `PillContent`. This is the *only* place a module's declared
/// appearance becomes pixels — the module never touches SwiftUI, and this view
/// never knows which module produced the content.
///
/// Freshness is styled here, uniformly: stale content dims and shows how long
/// ago it was confirmed, so a stale value can never masquerade as live.
public struct PillView: View {
    private let content: PillContent
    @State private var isHovering = false

    public init(_ content: PillContent) {
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let symbol = content.face.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .imageScale(.small)
                    .frame(width: 13, height: 13)   // fixed icon box; the glyph is
                    .clipped()                       // centred and can't spill onto
            }                                        // the text (no .fixedSize here)
            Text(content.face.text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
            if let staleLabel {
                Text(staleLabel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()   // the whole pill sizes to content, so the flank layout can't
                       // compress it (kept only on the container, not the children)
        .foregroundStyle(tintColor)
        .padding(.horizontal, 8)
        .frame(height: Self.pillHeight)   // matched height on both items
        // No box: like the native menu-bar items ("Help", the system SF Symbols),
        // this is just an icon + colored text sitting directly on the bar, so it
        // matches whatever tint macOS gives the menu bar — never a clashing panel.
        // A whisper-faint fill only appears on hover, the way native items do.
        .background(
            RoundedRectangle(cornerRadius: Self.pillRadius, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.14 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.pillRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .opacity(isDimmed ? 0.5 : 1)
        .help(content.face.tooltip ?? "")
    }

    /// Sizing tuned to sit flush in the menu bar like a native item.
    static let pillHeight: CGFloat = 22
    static var pillRadius: CGFloat { 6 }

    private var tintColor: Color {
        switch content.face.tint {
        case .neutral:  return Color(white: 0.9)
        case .good:     return Color(red: 0.25, green: 0.73, blue: 0.31)
        case .warning:  return Color(red: 0.89, green: 0.70, blue: 0.25)
        case .critical: return Color(red: 1.00, green: 0.42, blue: 0.37)
        case .info:     return Color(red: 0.42, green: 0.71, blue: 1.00)
        case .accent:   return Color(red: 0.72, green: 0.63, blue: 1.00)
        }
    }

    private var isDimmed: Bool {
        switch content.freshness {
        case .live: return false
        default:    return true
        }
    }

    /// "2m" style label for stale content; nil otherwise.
    private var staleLabel: String? {
        guard case let .stale(since) = content.freshness else { return nil }
        let seconds = Int(Date().timeIntervalSince(since))
        if seconds < 60 { return "\(max(0, seconds))s" }
        return "\(seconds / 60)m"
    }
}
