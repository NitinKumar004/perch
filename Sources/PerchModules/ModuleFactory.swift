import Foundation
import PerchCore
import PerchModuleKit
import PerchGitHub
import PerchConfig

/// Turns a config `SlotBinding` (a module id + settings) into a runnable module,
/// by looking the id up in the one `ModuleSpecs` registry and calling that
/// module's own `make`. The per-module construction knowledge lives in the spec
/// next to its catalog metadata — so adding a module is one entry in
/// `ModuleSpecs.all`, and the picker, the catalog and this factory all follow.
public struct ModuleFactory: Sendable {
    private let deps: ModuleDependencies

    public init(apiClient: GitHubAPIClient, timerController: TimerController,
                clipboardController: ClipboardController,
                fileShelfController: FileShelfController,
                thresholds: MetricThresholds = .standard,
                runHistory: RunHistoryStore = RunHistoryStore()) {
        self.deps = ModuleDependencies(
            apiClient: apiClient, timerController: timerController,
            clipboardController: clipboardController, fileShelfController: fileShelfController,
            thresholds: thresholds, runHistory: runHistory)
    }

    /// Build the module named by `binding`, applying its settings, or `nil` if
    /// the id is unknown — the caller skips an unresolved binding rather than
    /// crashing, so an old config referencing a removed module still loads.
    public func makeModule(for binding: SlotBinding) -> AnyNotchModule? {
        ModuleSpecs.make(binding, deps)
    }
}
