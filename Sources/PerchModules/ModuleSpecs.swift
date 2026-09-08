import Foundation
import PerchCore
import PerchModuleKit
import PerchGitHub
import PerchConfig

/// Which family a module belongs to, for grouping in the picker. Declared per
/// module rather than inferred from its settings, so a module is never
/// mis-grouped by a heuristic (e.g. "has a `url` setting ⇒ web").
public enum ModuleCategory: String, Sendable, Equatable {
    case local   // runs on your Mac, zero setup
    case github  // needs a GitHub connection
    case web     // pings a URL you provide
}

/// The runtime dependencies a module may need to be built. Passed to a spec's
/// `make` so the construction knowledge stays with the module, not in a factory
/// switch.
public struct ModuleDependencies: Sendable {
    public let apiClient: GitHubAPIClient
    public let timerController: TimerController
    public let clipboardController: ClipboardController
    public let fileShelfController: FileShelfController
    /// User-tunable warn/critical levels, injected so the metric modules colour
    /// by the user's chosen levels — the same whether shown alone or in Combined.
    public let thresholds: MetricThresholds

    public init(apiClient: GitHubAPIClient, timerController: TimerController,
                clipboardController: ClipboardController,
                fileShelfController: FileShelfController,
                thresholds: MetricThresholds = .standard) {
        self.apiClient = apiClient
        self.timerController = timerController
        self.clipboardController = clipboardController
        self.fileShelfController = fileShelfController
        self.thresholds = thresholds
    }
}

/// Everything the app needs to know about one module in ONE place: its picker
/// metadata (via `entry`), whether it's user-pickable (`hidden`), and how to
/// build a runnable instance from a binding (`make`).
///
/// This is the single source of truth the audit called for: `ModuleCatalog`
/// (the picker), `ModuleFactory` (construction) and the settings UI all derive
/// from `ModuleSpecs.all`, so adding a module is exactly one entry here — the
/// three lists can no longer drift out of sync.
public struct ModuleSpec: Sendable {
    public let entry: CatalogEntry
    /// Constructible from config but not offered in the picker (dev/test modules).
    public let hidden: Bool
    /// Build a runnable module from its binding, or nil if the settings are invalid.
    public let make: @Sendable (SlotBinding, ModuleDependencies) -> AnyNotchModule?

    public var id: String { entry.id }
}

/// The one registry. Every module the app knows about is listed here once.
public enum ModuleSpecs {
    public static func spec(id: String) -> ModuleSpec? {
        all.first { $0.id == id }
    }

    /// Build the module named by `binding`, or nil for an unknown id — the one
    /// resolution path, shared by the factory and by Combined's recursion.
    public static func make(_ binding: SlotBinding, _ deps: ModuleDependencies) -> AnyNotchModule? {
        spec(id: binding.module)?.make(binding, deps)
    }

    public static let all: [ModuleSpec] = [
        spec(GitHubBuildsModule.self, category: .github, tag: "one repo's CI",
             settings: [
                ModuleSetting(key: "repo", label: "Repository", placeholder: "owner/name"),
                ModuleSetting(key: "branch", label: "Branch", placeholder: "main", defaultValue: "main"),
                refreshSetting("60"),
             ]) { binding, deps in
            let repo = binding.settings["repo"] ?? "NitinKumar004/perch"
            let branch = binding.settings["branch"] ?? "main"
            let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return AnyNotchModule(GitHubBuildsModule(client: deps.apiClient, owner: parts[0], repo: parts[1], branch: branch))
        },

        spec(GitHubPRsModule.self, category: .github, tag: "review queue",
             settings: [
                ModuleSetting(key: "queue", label: "Show", placeholder: "",
                              defaultValue: "review-requested",
                              options: [
                                SettingOption(value: "review-requested", label: "PRs waiting on my review"),
                                SettingOption(value: "author", label: "PRs I opened"),
                              ]),
                ModuleSetting(key: "repo", label: "Repositories (optional)", placeholder: "owner/a, owner/b — blank = all repos"),
                ModuleSetting(key: "showChecks", label: "Show CI status", placeholder: "", defaultValue: "true", kind: .toggle),
                ModuleSetting(key: "showReview", label: "Show review status", placeholder: "", defaultValue: "true", kind: .toggle),
                ModuleSetting(key: "limit", label: "How many to list", placeholder: "8", defaultValue: "8"),
                refreshSetting("90"),
             ]) { _, deps in AnyNotchModule(GitHubPRsModule(client: deps.apiClient)) },

        spec(MultiBuildsModule.self, category: .github, tag: "many repos' CI",
             settings: [
                ModuleSetting(key: "repos", label: "Repositories", placeholder: "owner/a, owner/b, owner/c"),
                ModuleSetting(key: "branch", label: "Branch", placeholder: "main", defaultValue: "main"),
                refreshSetting("90"),
             ]) { _, deps in AnyNotchModule(MultiBuildsModule(client: deps.apiClient)) },

        spec(GitHubNotificationsModule.self, category: .github, tag: "unread bell",
             settings: [refreshSetting("60")]) { _, deps in
            AnyNotchModule(GitHubNotificationsModule(client: deps.apiClient))
        },

        spec(DeployModule.self, category: .web, tag: "URL up / down",
             settings: [
                ModuleSetting(key: "url", label: "Health URL", placeholder: "https://example.com/health"),
                refreshSetting("20"),
             ]) { _, _ in AnyNotchModule(DeployModule()) },

        spec(CombinedModule.self, category: .local, tag: "several in one",
             settings: CombinedModule.combinable().map { m in
                ModuleSetting(key: m.key, label: m.label, placeholder: "",
                              defaultValue: m.on ? "true" : "false", kind: .toggle)
             } + [refreshSetting("2")]) { binding, deps in
            let members = CombinedModule.enabledMemberIDs(from: binding.settings)
                .compactMap { ModuleSpecs.make(SlotBinding(module: $0), deps) }
            guard !members.isEmpty else { return nil }
            return AnyNotchModule(CombinedModule(members: members))
        },

        spec(VitalsModule.self, category: .local, tag: "usage %",
             settings: [refreshSetting("2")]) { _, deps in AnyNotchModule(VitalsModule(thresholds: deps.thresholds)) },

        spec(MemoryModule.self, category: .local, tag: "RAM in use",
             settings: [refreshSetting("2")]) { _, deps in AnyNotchModule(MemoryModule(thresholds: deps.thresholds)) },

        spec(NetworkModule.self, category: .local, tag: "up / down",
             settings: [refreshSetting("2")]) { _, _ in AnyNotchModule(NetworkModule()) },

        spec(ThermalModule.self, category: .local, tag: "throttle pressure",
             settings: [refreshSetting("5")]) { _, _ in AnyNotchModule(ThermalModule()) },

        spec(SwapModule.self, category: .local, tag: "thrash warning",
             settings: [refreshSetting("3")]) { _, deps in AnyNotchModule(SwapModule(thresholds: deps.thresholds)) },

        spec(LoadModule.self, category: .local, tag: "system load",
             settings: [refreshSetting("3")]) { _, deps in AnyNotchModule(LoadModule(thresholds: deps.thresholds)) },

        spec(DiskModule.self, category: .local, tag: "free space",
             settings: [
                ModuleSetting(key: "path", label: "Volume path", placeholder: "/", defaultValue: "/"),
                refreshSetting("30"),
             ]) { _, deps in AnyNotchModule(DiskModule(thresholds: deps.thresholds)) },

        spec(ClipboardModule.self, category: .local, tag: "recent copies",
             settings: []) { _, deps in AnyNotchModule(ClipboardModule(controller: deps.clipboardController)) },

        spec(FileShelfModule.self, category: .local, tag: "stash files",
             settings: []) { _, deps in AnyNotchModule(FileShelfModule(controller: deps.fileShelfController)) },

        spec(PortMonitorModule.self, category: .local, tag: "port up?",
             settings: [
                ModuleSetting(key: "port", label: "Port", placeholder: "3000", defaultValue: "3000"),
                ModuleSetting(key: "label", label: "Label (optional)", placeholder: ":3000"),
                refreshSetting("5"),
             ]) { _, _ in AnyNotchModule(PortMonitorModule()) },

        spec(BatteryModule.self, category: .local, tag: "charge %",
             settings: []) { _, _ in AnyNotchModule(BatteryModule()) },

        spec(TimerModule.self, category: .local, tag: "pomodoro",
             settings: [
                ModuleSetting(key: "minutes", label: "Minutes", placeholder: "25", defaultValue: "25"),
             ]) { _, deps in AnyNotchModule(TimerModule(controller: deps.timerController)) },

        spec(CalendarModule.self, category: .local, tag: "next meeting",
             settings: [
                ModuleSetting(key: "lookaheadHours", label: "Look ahead (hours)", placeholder: "12", defaultValue: "12"),
                refreshSetting("30"),
             ]) { _, _ in AnyNotchModule(CalendarModule()) },

        spec(ClockModule.self, category: .local, tag: "the time",
             settings: [
                ModuleSetting(key: "format", label: "Time format", placeholder: "",
                              defaultValue: "24",
                              options: [
                                SettingOption(value: "24", label: "24-hour (14:30)"),
                                SettingOption(value: "12", label: "12-hour (2:30 PM)"),
                              ]),
                ModuleSetting(key: "showSeconds", label: "Show seconds", placeholder: "",
                              defaultValue: "false", kind: .toggle),
             ]) { _, _ in AnyNotchModule(ClockModule()) },

        // Dev/test module: resolvable if a config references it, but never offered
        // in the picker. `hidden` keeps it out of the catalog without the old
        // drift (a factory case with no catalog entry).
        spec(FakeBuildModule.self, category: .github, tag: "", hidden: true,
             settings: []) { _, _ in AnyNotchModule(FakeBuildModule()) },
    ]

    /// Build one spec from a module type's own descriptor, so id/name/summary/
    /// requiresConnection never get re-typed and can't drift from the module.
    private static func spec<M: NotchModule>(
        _ type: M.Type, category: ModuleCategory, tag: String, hidden: Bool = false,
        settings: [ModuleSetting],
        make: @escaping @Sendable (SlotBinding, ModuleDependencies) -> AnyNotchModule?
    ) -> ModuleSpec {
        let d = M.descriptor
        return ModuleSpec(
            entry: CatalogEntry(id: d.id, name: d.name, summary: d.summary,
                                requiresConnection: d.requiresConnection,
                                category: category, tag: tag, settings: settings),
            hidden: hidden, make: make)
    }

    /// The shared "refresh every N seconds" setting.
    private static func refreshSetting(_ placeholder: String) -> ModuleSetting {
        ModuleSetting(key: "refreshSeconds", label: "Refresh every (sec)", placeholder: placeholder)
    }
}
