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
                if model.hudPosition == .flank {
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
        .animation(.easeInOut(duration: 0.2), value: model.leftPill)
        .animation(.easeInOut(duration: 0.2), value: model.rightPill)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.isPanelOpen)
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

    private func pill(_ content: PillContent) -> some View {
        PillView(content)
            .contentShape(Capsule())
            .onTapGesture { onActivate() }
            .transition(.opacity)
    }
}
