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
                case .panel:     break // panel rendering arrives in a later phase
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
