import SwiftUI
import PerchModuleKit

/// The content hosted in the notch window: a left pill and a right pill with a
/// transparent gap the exact width of the physical notch between them, so the
/// pills sit flush on either side of the real hardware.
public struct NotchRootView: View {
    /// The name of the coordinate space the interactive-frame reporters measure
    /// in — anchored at the root, so the frames line up 1:1 with the flipped
    /// AppKit container that hit-tests them.
    public static let coordinateSpace = "notchRoot"

    @State private var model: NotchViewModel
    private let onActivate: () -> Void
    private let panelActions: PanelActions
    /// Called with the frames of the actually-interactive bits (pills, banner,
    /// open panel) in `coordinateSpace`. The AppKit host uses these to pass every
    /// OTHER click straight through to the menu bar beneath — so a wide window
    /// centred on the notch never blocks the app menus or menu-bar extras.
    private let onInteractiveFrames: ([CGRect]) -> Void

    public init(model: NotchViewModel,
                onActivate: @escaping () -> Void = {},
                panelActions: PanelActions = PanelActions(),
                onInteractiveFrames: @escaping ([CGRect]) -> Void = { _ in }) {
        self._model = State(initialValue: model)
        self.onActivate = onActivate
        self.panelActions = panelActions
        self.onInteractiveFrames = onInteractiveFrames
    }

    public var body: some View {
        VStack(spacing: 8) {
            Group {
                // A transient alert takes over the pill row IN PLACE (same bar,
                // no card hanging below the notch), then reverts to the pills.
                // Shown even when the panel is open, so an auto-open's "why"
                // banner is visible in the notch above the opened panel.
                if let banner = model.banner {
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
                    .reportsInteractive()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(InteractiveFramesKey.self) { onInteractiveFrames($0) }
        .environment(\.theme, model.themeStyle)   // full identity: colour + font + shape + material
        .environment(\.palette, model.palette)    // colour-only views keep reading this
        .animation(.easeInOut(duration: 0.2), value: model.leftPill)
        .animation(.easeInOut(duration: 0.2), value: model.rightPill)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.isPanelOpen)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: model.banner)
    }

    /// Pills pushed to opposite edges to flank the physical notch.
    private var flankRow: some View {
        HStack(spacing: 0) {
            flankHalf(pushTo: .trailing) { if let left = model.leftPill { pill(left) } }
            // The physical notch lives here — draw nothing, pass clicks through.
            Color.clear.frame(width: max(model.notchWidth, 12)).allowsHitTesting(false)
            flankHalf(pushTo: .leading) { if let right = model.rightPill { pill(right) } }
        }
    }

    /// One side of the flank row. The pill is pinned toward the notch and the
    /// OUTER empty area is filled by a non-hittable `Spacer`, so clicks over that
    /// area — the app menus on the left, the menu extras (Spotlight, Wi-Fi…) on
    /// the right — fall straight through to the menu bar instead of being
    /// swallowed by the window. The `maxWidth: .infinity` keeps each half exactly
    /// half the row, so the notch gap stays centered on the physical notch
    /// whatever the pill widths. (A plain `.frame(alignment:)` left the outer half
    /// as flexible frame space that still ate the click — this is the fix.)
    @ViewBuilder
    private func flankHalf<Content: View>(pushTo edge: HorizontalEdge,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            if edge == .trailing { Spacer(minLength: 0) }
            content()
            if edge == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    /// Pills grouped together (right-of-notch / below layouts). In the
    /// right-of-notch layout the window sits just right of the notch, so the pills
    /// hug the LEFT (next to the notch) — that keeps a wide combined pill from
    /// growing into the menu-bar extras on the far right. The below layout is
    /// centred under the menu bar as usual.
    private var groupedRow: some View {
        HStack(spacing: 6) {
            if let left = model.leftPill { pill(left) }
            if let right = model.rightPill { pill(right) }
        }
        .frame(maxWidth: .infinity, alignment: model.hudPosition == .right ? .leading : .center)
    }

    /// The alert shown in-place in the pill row. It takes over whichever pill is
    /// *bigger* (more text → more room), and the other pill stays put — so a pill
    /// is never yanked from its place. Grouped/below layouts centre the banner.
    @ViewBuilder
    private func bannerRow(_ banner: BannerAlert) -> some View {
        let capsule = BannerView(banner) { onActivate() }
            .reportsInteractive()
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        if model.hudPosition == .flank {
            let bannerOnRight = BannerPlacement.showOnRight(left: model.leftPill, right: model.rightPill)
            HStack(spacing: 0) {
                flankHalf(pushTo: .trailing) {
                    if bannerOnRight { if let left = model.leftPill { pill(left) } }
                    else { capsule }
                }
                Color.clear.frame(width: max(model.notchWidth, 12)).allowsHitTesting(false)
                flankHalf(pushTo: .leading) {
                    if bannerOnRight { capsule }
                    else { if let right = model.rightPill { pill(right) } }
                }
            }
        } else {
            capsule.frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func pill(_ content: PillContent) -> some View {
        PillView(content)
            .contentShape(Capsule())
            .onTapGesture { onActivate() }
            .reportsInteractive()
            .transition(.opacity)
    }
}

/// Collects the frames of the interactive views (pills, banner, open panel) so
/// the AppKit host can hit-test precisely and pass every other click through.
private struct InteractiveFramesKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    /// Publish this view's frame (in the notch-root coordinate space) as an
    /// interactive region — clicks that land here are the app's, everything else
    /// falls through to the menu bar.
    func reportsInteractive() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InteractiveFramesKey.self,
                    value: [proxy.frame(in: .named(NotchRootView.coordinateSpace))])
            }
        )
    }
}
