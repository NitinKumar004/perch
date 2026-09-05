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
    private var tasks: [Task<Void, Never>] = []

    init(model: NotchViewModel, context: ModuleContext) {
        self.model = model
        self.baseContext = context
    }

    /// Bind a module to a slot, handing it the settings the user configured for
    /// this placement (repo, branch, filters, …).
    func bind(_ module: AnyNotchModule, to slot: Slot, settings: [String: String] = [:]) {
        let context = ModuleContext(clock: baseContext.clock, settings: settings)
        let stream = module.pillStream(context, slot: slot)
        let task = Task { @MainActor [model] in
            for await content in stream {
                switch slot {
                case .leftPill:  model.leftPill = content
                case .rightPill: model.rightPill = content
                case .panel:     break
                }
            }
        }
        tasks.append(task)
    }

    /// Bind a module into the panel stack at `index`, labelled with its name.
    /// Panel rows update independently as each module streams new content.
    func bindPanel(_ module: AnyNotchModule, at index: Int, settings: [String: String] = [:]) {
        let id = "\(module.descriptor.id)#\(index)"
        let title = module.descriptor.name
        let context = ModuleContext(clock: baseContext.clock, settings: settings)
        let stream = module.pillStream(context, slot: .panel)

        // Seed the row so ordering is stable before the first value arrives.
        model.panelItems.append(PanelItem(
            id: id, title: title,
            content: PillContent(face: module.descriptor.placeholderFace, freshness: .unknown, asOf: Date())))

        let task = Task { @MainActor [model] in
            for await content in stream {
                if let row = model.panelItems.firstIndex(where: { $0.id == id }) {
                    model.panelItems[row].content = content
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
