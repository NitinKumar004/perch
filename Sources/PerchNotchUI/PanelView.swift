import SwiftUI
import PerchCore
import PerchModuleKit

/// The drop-down detail card that appears below the notch when opened. It lists
/// each configured panel module as a labelled row — the module's name, its
/// pill, and an honest freshness note. This is the "report" surface.
struct PanelView: View {
    let items: [PanelItem]

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
}
