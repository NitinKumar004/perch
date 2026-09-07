import SwiftUI
import PerchModuleKit

/// The content hosted in the notch window: a left pill and a right pill with a
/// transparent gap the exact width of the physical notch between them, so the
/// pills sit flush on either side of the real hardware.
public struct NotchRootView: View {
    @State private var model: NotchViewModel
    private let onActivate: () -> Void
    private let panelActions: PanelActions

    public init(model: NotchViewModel,
                onActivate: @escaping () -> Void = {},
                panelActions: PanelActions = PanelActions()) {
        self._model = State(initialValue: model)
        self.onActivate = onActivate
        self.panelActions = panelActions
    }

    public var body: some View {
        VStack(spacing: 8) {
            Group {
                // A transient alert takes over the pill row IN PLACE (same bar,
                // no card hanging below the notch), then reverts to the pills.
                if let banner = model.banner, !model.isPanelOpen {
                    bannerRow(banner)
                } else if model.hudPosition == .flank {
                    flankRow
                } else {
                    groupedRow
                }
            }
            .frame(height: 34)

            if model.isPanelOpen {
                PanelView(items: model.panelItems, isConnected: model.isConnected, actions: panelActions)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.palette, model.palette)   // the active theme skins everything below
        .animation(.easeInOut(duration: 0.2), value: model.leftPill)
        .animation(.easeInOut(duration: 0.2), value: model.rightPill)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.isPanelOpen)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: model.banner)
    }

    /// Pills pushed to opposite edges to flank the physical notch.
    private var flankRow: some View {
        HStack(spacing: 0) {
            Group { if let left = model.leftPill { pill(left) } }
                .frame(maxWidth: .infinity, alignment: .trailing)
            // The physical notch lives here — draw nothing, pass clicks through.
            Color.clear.frame(width: max(model.notchWidth, 12)).allowsHitTesting(false)
            Group { if let right = model.rightPill { pill(right) } }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Pills grouped together (right-of-notch / below layouts).
    private var groupedRow: some View {
        HStack(spacing: 6) {
            if let left = model.leftPill { pill(left) }
            if let right = model.rightPill { pill(right) }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The alert shown in-place in the pill row. It takes over whichever pill is
    /// *bigger* (more text → more room), and the other pill stays put — so a pill
    /// is never yanked from its place. Grouped/below layouts centre the banner.
    @ViewBuilder
    private func bannerRow(_ banner: BannerAlert) -> some View {
        let capsule = BannerView(banner) { onActivate() }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        if model.hudPosition == .flank {
            let bannerOnRight = BannerPlacement.showOnRight(left: model.leftPill, right: model.rightPill)
            HStack(spacing: 0) {
                Group {
                    if bannerOnRight { if let left = model.leftPill { pill(left) } }
                    else { capsule }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Color.clear.frame(width: max(model.notchWidth, 12)).allowsHitTesting(false)
                Group {
                    if bannerOnRight { capsule }
                    else { if let right = model.rightPill { pill(right) } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            capsule.frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func pill(_ content: PillContent) -> some View {
        PillView(content)
            .contentShape(Capsule())
            .onTapGesture { onActivate() }
            .transition(.opacity)
    }
}
