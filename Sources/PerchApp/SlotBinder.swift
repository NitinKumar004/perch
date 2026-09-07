import Foundation
import PerchCore
import PerchModuleKit
import PerchNotchUI

/// Connects a module's pill stream to a slot in the view model.
///
/// This is the live data loop made explicit: for each bound module it consumes
/// the stream of `PillContent` and writes it to the matching slot on the main
/// actor. The view model then re-renders only that pill. Binding is the entire
/// contract between "a module" and "the screen".
@MainActor
final class SlotBinder {
    private let model: NotchViewModel
    private let baseContext: ModuleContext
    private let notifier: Notifier
    private let onCritical: () -> Void
    private let onStatusChange: () -> Void
    /// Show a transient in-notch banner for an alert that was actually delivered
    /// (deduped, not during quiet hours). Carries the severity tint.
    private let onBanner: (BannerAlert) -> Void
    private var tasks: [Task<Void, Never>] = []

    /// - Parameters:
    ///   - onCritical: called once each time a bound module's pill transitions
    ///     into a critical (red) state, so the shell can auto-open.
    ///   - onStatusChange: called after every render, so the shell can refresh
    ///     the menu-bar icon to reflect the worst current state.
    init(model: NotchViewModel, context: ModuleContext, notifier: Notifier,
         onCritical: @escaping () -> Void = {},
         onStatusChange: @escaping () -> Void = {},
         onBanner: @escaping (BannerAlert) -> Void = { _ in }) {
        self.model = model
        self.baseContext = context
        self.notifier = notifier
        self.onCritical = onCritical
        self.onStatusChange = onStatusChange
        self.onBanner = onBanner
    }

    /// Seed a panel row so ordering is stable before the first value arrives.
    func seedPanelItem(id: String, module: AnyNotchModule) {
        model.panelItems.append(PanelItem(
            id: id, title: module.descriptor.name,
            content: PillContent(face: module.descriptor.placeholderFace, freshness: .unknown, asOf: Date())))
    }

    /// Bind ONE module poll (a single stream) and fan its render out to every
    /// slot that uses the same module + settings — the pills it occupies and the
    /// panel rows with the given ids. This coalesces duplicate pollers: a module
    /// placed in both a pill and the panel hits the network once, not twice.
    ///
    /// This is correct because a module's `face` is slot-independent — the pill
    /// looks the same wherever it sits; only the panel adds detail rows.
    func bindShared(_ module: AnyNotchModule, settings: [String: String],
                    pills: Set<Slot>, panelIDs: [String]) {
        let context = ModuleContext(clock: baseContext.clock, settings: settings)
        let opensOnCritical = module.descriptor.opensPanelOnCritical
        let stream = module.renderStream(context, slot: .panel)  // slot-independent face
        let task = Task { @MainActor [model, notifier, onCritical, onStatusChange, onBanner] in
            // nil until the first *live* render establishes a baseline. Only
            // real observations count: a module yields a `.unknown` placeholder
            // seed before its first poll, so if we baselined on the seed, the
            // first real value of an already-failing build would look like a
            // fresh good→red transition and pop the panel on every launch/reload.
            // Baselining on the first live render fixes that — an already-red
            // build shows in the red menu-bar bird; only a genuine good→red
            // transition DURING the session auto-opens.
            var tracker = AutoOpenTracker(opensOnCritical: opensOnCritical)
            for await render in stream {
                if let alert = render.alert, notifier.post(alert) == .delivered,
                   !model.isPanelOpen {   // the open panel already shows everything
                    onBanner(BannerAlert(id: alert.id, title: alert.title, body: alert.body,
                                         tint: render.pill.face.tint, url: alert.url))
                }
                if tracker.observe(isCritical: render.pill.face.tint == .critical,
                                   isLive: render.pill.freshness.isTrustworthy) {
                    onCritical()
                }
                if pills.contains(.leftPill) { model.leftPill = render.pill }
                if pills.contains(.rightPill) { model.rightPill = render.pill }
                for id in panelIDs {
                    if let row = model.panelItems.firstIndex(where: { $0.id == id }) {
                        model.panelItems[row].content = render.pill
                        model.panelItems[row].detail = render.detail
                        model.panelItems[row].subtitle = render.contextLabel
                    }
                }
                onStatusChange()
            }
        }
        tasks.append(task)
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
