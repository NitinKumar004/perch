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

    public init() {}
}

/// One labelled row in the panel.
public struct PanelItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public var content: PillContent

    public init(id: String, title: String, content: PillContent) {
        self.id = id
        self.title = title
        self.content = content
    }
}
