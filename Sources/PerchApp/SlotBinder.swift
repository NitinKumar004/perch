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
    /// Dwell + cooldown damping for auto-open/banner (hysteresis is automatic).
    private let pacing: AlertPacing

    init(model: NotchViewModel, context: ModuleContext, notifier: Notifier,
         pacing: AlertPacing = .standard,
         onCritical: @escaping () -> Void = {},
         onStatusChange: @escaping () -> Void = {},
         onBanner: @escaping (BannerAlert) -> Void = { _ in }) {
        self.model = model
        self.baseContext = context
        self.notifier = notifier
        self.pacing = pacing
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
        let pacing = self.pacing
        let task = Task { @MainActor [model, notifier, onCritical, onStatusChange, onBanner] in
            // The tracker owns the baseline / dwell / hysteresis / cooldown rules
            // (see AutoOpenTracker). A non-live seed is ignored, an already-red
            // metric at launch is a silent baseline, and a value flapping at its
            // threshold peeks once — not on every crossing.
            var tracker = AutoOpenTracker(opensOnCritical: opensOnCritical,
                                          dwell: TimeInterval(pacing.dwellSeconds),
                                          cooldown: TimeInterval(pacing.cooldownSeconds))
            for await render in stream {
                let didAutoOpen = tracker.observe(tint: render.pill.face.tint,
                                                  isLive: render.pill.freshness.isTrustworthy,
                                                  now: render.pill.asOf)
                if didAutoOpen { onCritical() }

                // Banner: a delivered alert surfaces in the notch pill — even over
                // an open panel — so a notification is never silently missed.
                // (post() still dedups and honours quiet hours; the notchBanner
                // setting still gates it in the app.) A module's OWN *red* alert
                // (e.g. memory's sustained-high) is held to the SAME cooldown as
                // the auto-open, so a red-flapping metric can't out-nag the user's
                // pace through its own channel; amber ("serious") and event alerts
                // (GitHub) pass through, and a same-tick auto-open already cleared
                // the gate so its richer alert still shows. If a metric auto-opened
                // without its own alert, a banner that says WHY.
                if let alert = render.alert {
                    // Cooldown-gate only a RED alert that didn't already auto-open
                    // (a same-tick auto-open passed the tracker's gate, so its
                    // richer alert shows). `admitRedAlert` is consulted only here,
                    // so a red tick without a module alert never consumes cooldown.
                    let alertIsRed = render.pill.face.tint == .critical
                    let admit = !alertIsRed || didAutoOpen || tracker.admitRedAlert(now: render.pill.asOf)
                    if admit, notifier.post(alert) == .delivered {
                        onBanner(BannerAlert(id: alert.id, title: alert.title, body: alert.body,
                                             tint: render.pill.face.tint, url: alert.url))
                    }
                } else if didAutoOpen {
                    // Disambiguate by the reason (the specific metric) so two
                    // different modules auto-opening in the same one-second token
                    // window don't collide on the id and get the second silently
                    // dropped by the banner queue's dedup.
                    let reason = Self.autoOpenReason(render)
                    onBanner(BannerAlert(id: "autoopen-\(reason)-\(AlertEpisode.token())",
                                         title: reason,
                                         body: "reached a critical level",
                                         tint: .critical, url: nil))
                    // This banner doesn't go through post() (no native
                    // notification), so play the configured sound here too — else a
                    // metric crossing red while you're busy surfaces silently.
                    notifier.playConfiguredSound()
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

    /// A short reason for an auto-open: the specific metric that went red (its
    /// panel-row title + value — so a Combined pill names the culprit, e.g.
    /// "Swap used 9.0 GB"), falling back to the pill text.
    nonisolated static func autoOpenReason(_ render: ModuleRender) -> String {
        if let crit = render.detail.first(where: { $0.tint == .critical }) {
            if let sub = crit.subtitle, !sub.isEmpty { return "\(crit.title) \(sub)" }
            return crit.title
        }
        return render.pill.face.text.isEmpty ? "A metric" : render.pill.face.text
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
