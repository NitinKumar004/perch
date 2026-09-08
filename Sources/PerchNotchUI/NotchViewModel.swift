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
    /// The self-update state — drives the Settings window's update button (label,
    /// tappability, emphasis), so the whole check → download → install flow is
    /// reachable from there without hunting for the menu-bar bird.
    public var updateStatus: UpdateAvailability = .idle
    /// The active theme identity (colour + typeface + shape + material) from the
    /// user's chosen theme and their accent/material overrides. Injected into the
    /// view tree so every pill and the panel re-skin — and re-shape, re-font,
    /// re-material — when it changes.
    public var themeStyle: ThemeStyle = .system
    /// The active palette — derived from `themeStyle` so colour has ONE source of
    /// truth. Colour-only views keep reading `\.palette`; richer views read the
    /// full `\.theme`.
    public var palette: Palette { themeStyle.palette }
    /// Width of the physical notch gap, updated when displays change so the pills
    /// stay flush on either side (0 on non-notch Macs → pills sit together).
    public var notchWidth: CGFloat = 0
    /// Where the HUD sits — drives both the window frame and the pill layout.
    public var hudPosition: HUDPosition = .flank
    /// The transient alert currently shown in the notch, or nil. Driven by the
    /// BannerPresenter; it renders in-place in the pill row (no window resize).
    public var banner: BannerAlert?

    public init() {}
}

/// Where the HUD sits on screen.
public enum HUDPosition: String, Sendable, CaseIterable {
    /// Flanking the notch in the menu bar (the intended look on notch Macs).
    case flank
    /// Both pills grouped just right of the notch — dodges the app menus on the
    /// left, good when the menu bar is busy.
    case right
    /// Grouped and hanging just below the menu bar — for non-notch displays.
    case below
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
