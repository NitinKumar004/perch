import SwiftUI

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
            HStack(spacing: 0) {
                Group {
                    if let left = model.leftPill {
                        PillView(left)
                            .contentShape(Capsule())
                            .onTapGesture { onActivate() }
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // The physical notch lives here — draw nothing, and let clicks
                // pass straight through to the menu bar underneath.
                Color.clear.frame(width: max(model.notchWidth, 12)).allowsHitTesting(false)

                Group {
                    if let right = model.rightPill {
                        PillView(right)
                            .contentShape(Capsule())
                            .onTapGesture { onActivate() }
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
}
