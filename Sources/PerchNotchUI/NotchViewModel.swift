import Foundation
import Observation
import PerchModuleKit

/// The single source of UI truth for the notch surface. The composition root
/// feeds it `PillContent` as modules produce it; SwiftUI re-renders only the
/// pill that actually changed.
///
/// `@Observable` + `@MainActor`: reads are cheap and updates are always applied
/// on the main thread, so the UI never races with a background provider.
@MainActor
@Observable
public final class NotchViewModel {
    public var leftPill: PillContent?
    public var rightPill: PillContent?

    /// The stacked rows shown in the drop-down panel, in config order. Each
    /// carries the module's name alongside its rendered content so the panel can
    /// label rows.
    public var panelItems: [PanelItem] = []
    /// Whether the drop-down panel is currently open.
    public var isPanelOpen = false
    /// Whether GitHub is connected — drives the panel's "Connect" button.
    public var isConnected = false
    /// Width of the physical notch gap, updated when displays change so the pills
    /// stay flush on either side (0 on non-notch Macs → pills sit together).
    public var notchWidth: CGFloat = 0

    public init() {}
}

/// One module's section in the panel: a header (name + its pill) and the detail
/// rows it contributes.
public struct PanelItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// What this row is watching (repo, host, …), shown under the title.
    public var subtitle: String?
    public var content: PillContent
    public var detail: [DetailRow]

    public init(id: String, title: String, subtitle: String? = nil,
                content: PillContent, detail: [DetailRow] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.detail = detail
    }
}
