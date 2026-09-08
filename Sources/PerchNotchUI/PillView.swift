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
    @Environment(\.palette) private var palette

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
            // Render the text/segments block whenever there's text OR segments —
            // a combined pill whose members are ALL bar-only has empty fallback
            // text but non-empty segments, and must still draw its bars (not go
            // blank). A single bar-only pill (no segments) renders via `progress`.
            if !content.face.text.isEmpty || !(content.face.segments ?? []).isEmpty {
                pillText
                    // The flank layout animates leftPill/rightPill changes (a nice
                    // fade when a pill appears or its tint shifts). But a metric's
                    // *text* changes every tick — network throughput especially —
                    // and an animated text swap crossfades old over new, so the
                    // two strings overlap for the fade's duration. Swap instantly.
                    .contentTransition(.identity)
            }
            if let progress = content.face.progress {
                MiniBar(value: progress, color: tintColor)
                    .frame(width: 26, height: 5)   // glanceable level gauge, no jargon word
            }
            if let badge = content.face.badge {
                Circle()
                    .fill(palette.color(for: badge))
                    .frame(width: 6, height: 6)   // calm attention dot; the count is in the tooltip
            }
            if let staleLabel {
                Text(staleLabel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.ink(0.4))   // follows the theme, like the rest
            }
            if errorMessage != nil {
                // A distinct, actionable marker for a genuine error (misconfig,
                // auth) — so it never masquerades as a transient loading "…".
                // The message is in the tooltip.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.warning)
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
                .fill(palette.onSurface.opacity(isHovering ? 0.14 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: Self.pillRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .opacity(isDimmed ? 0.5 : 1)
        // Prefer the freshness error message in the tooltip so a misconfigured or
        // failing module explains itself on hover instead of a mute dimmed pill.
        .help(errorMessage ?? content.face.tooltip ?? "")
    }

    /// The carried error string when the value failed in a way worth surfacing.
    private var errorMessage: String? {
        if case let .error(message) = content.freshness { return message }
        return nil
    }

    /// Sizing tuned to sit flush in the menu bar like a native item.
    static let pillHeight: CGFloat = 22
    static var pillRadius: CGFloat { 6 }

    private var tintColor: Color { palette.color(for: content.face.tint) }

    /// The pill's text — either a single string, or, for a combined pill, one
    /// coloured segment per metric separated by a muted dot so each keeps its
    /// own status colour.
    @ViewBuilder private var pillText: some View {
        if let segments = content.face.segments, !segments.isEmpty {
            HStack(spacing: 5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                    if i > 0 { Text("·").foregroundStyle(palette.ink(0.3)) }
                    if let progress = seg.progress {
                        MiniBar(value: progress, color: palette.color(for: seg.tint))
                            .frame(width: 22, height: 5)   // a member shown as a gauge
                    } else {
                        Text(seg.text).foregroundStyle(palette.color(for: seg.tint))
                    }
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
        } else {
            Text(content.face.text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
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
