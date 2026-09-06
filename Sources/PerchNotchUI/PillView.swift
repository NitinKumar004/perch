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

    public init(_ content: PillContent) {
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let symbol = content.face.symbolName {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(content.face.text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
            if let staleLabel {
                Text(staleLabel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()   // natural size — stops the flank layout compressing the
                       // icon over the text (the cramped/overlapping pill bug)
        .foregroundStyle(tintColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .opacity(isDimmed ? 0.5 : 1)
        .help(content.face.tooltip ?? "")
    }

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
