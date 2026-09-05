import SwiftUI

/// The content hosted in the notch window: a left pill and a right pill with a
/// transparent gap the exact width of the physical notch between them, so the
/// pills sit flush on either side of the real hardware.
public struct NotchRootView: View {
    @State private var model: NotchViewModel
    private let notchWidth: CGFloat

    public init(model: NotchViewModel, notchWidth: CGFloat) {
        self._model = State(initialValue: model)
        self.notchWidth = notchWidth
    }

    public var body: some View {
        HStack(spacing: 0) {
            Group {
                if let left = model.leftPill {
                    PillView(left).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // The physical notch lives here — draw nothing.
            Color.clear.frame(width: max(notchWidth, 12))

            Group {
                if let right = model.rightPill {
                    PillView(right).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: model.leftPill)
        .animation(.easeInOut(duration: 0.2), value: model.rightPill)
    }
}
