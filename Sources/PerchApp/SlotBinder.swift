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
    private var tasks: [Task<Void, Never>] = []

    /// - Parameter onCritical: called once each time a bound module's pill
    ///   transitions into a critical (red) state, so the shell can auto-open.
    init(model: NotchViewModel, context: ModuleContext, notifier: Notifier,
         onCritical: @escaping () -> Void = {}) {
        self.model = model
        self.baseContext = context
        self.notifier = notifier
        self.onCritical = onCritical
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
        let stream = module.renderStream(context, slot: .panel)  // slot-independent face
        let task = Task { @MainActor [model, notifier, onCritical] in
            var wasCritical = false
            for await render in stream {
                if let alert = render.alert { notifier.post(alert) }
                // Fire on the transition into red, not on every red poll.
                let isCritical = render.pill.face.tint == .critical
                if isCritical && !wasCritical { onCritical() }
                wasCritical = isCritical
                if pills.contains(.leftPill) { model.leftPill = render.pill }
                if pills.contains(.rightPill) { model.rightPill = render.pill }
                for id in panelIDs {
                    if let row = model.panelItems.firstIndex(where: { $0.id == id }) {
                        model.panelItems[row].content = render.pill
                        model.panelItems[row].detail = render.detail
                        model.panelItems[row].subtitle = render.contextLabel
                    }
                }
            }
        }
        tasks.append(task)
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
