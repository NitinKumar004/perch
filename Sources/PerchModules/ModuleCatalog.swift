import Foundation
import PerchCore

/// One fixed choice for a setting rendered as a dropdown — a stored `value` and
/// a friendly `label`.
public struct SettingOption: Sendable, Equatable {
    public let value: String
    public let label: String
    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// A user-facing description of a setting a module accepts, so a settings UI can
/// render the right field without hard-coding any module's keys. When `options`
/// is set, the field is a dropdown; otherwise it's a free-text field.
public struct ModuleSetting: Sendable, Equatable {
    public let key: String
    public let label: String
    public let placeholder: String
    public let defaultValue: String
    public let options: [SettingOption]?

    public init(key: String, label: String, placeholder: String,
                defaultValue: String = "", options: [SettingOption]? = nil) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.options = options
    }
}

/// One entry in the catalog: a module's identity plus the settings it exposes.
public struct CatalogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let requiresConnection: Bool
    public let settings: [ModuleSetting]
}

/// The list of every module a user can place, with the settings each accepts.
/// This is the single source the settings UI reads — add a module here and it
/// becomes fully configurable in the UI, no UI code changes.
public enum ModuleCatalog {
    public static func all() -> [CatalogEntry] {
        [
            CatalogEntry(
                id: GitHubBuildsModule.descriptor.id,
                name: GitHubBuildsModule.descriptor.name,
                summary: GitHubBuildsModule.descriptor.summary,
                requiresConnection: true,
                settings: [
                    ModuleSetting(key: "repo", label: "Repository", placeholder: "owner/name"),
                    ModuleSetting(key: "branch", label: "Branch", placeholder: "main", defaultValue: "main"),
                ]),
            CatalogEntry(
                id: GitHubPRsModule.descriptor.id,
                name: GitHubPRsModule.descriptor.name,
                summary: GitHubPRsModule.descriptor.summary,
                requiresConnection: true,
                settings: [
                    ModuleSetting(key: "queue", label: "Show", placeholder: "",
                                  defaultValue: "review-requested",
                                  options: [
                                    SettingOption(value: "review-requested", label: "PRs waiting on my review"),
                                    SettingOption(value: "author", label: "PRs I opened"),
                                  ]),
                    ModuleSetting(key: "repo", label: "Repository (optional)", placeholder: "owner/name — blank = all repos"),
                ]),
            CatalogEntry(
                id: DeployModule.descriptor.id,
                name: DeployModule.descriptor.name,
                summary: DeployModule.descriptor.summary,
                requiresConnection: false,
                settings: [
                    ModuleSetting(key: "url", label: "Health URL", placeholder: "https://example.com/health"),
                ]),
            CatalogEntry(
                id: VitalsModule.descriptor.id,
                name: VitalsModule.descriptor.name,
                summary: VitalsModule.descriptor.summary,
                requiresConnection: false, settings: []),
            CatalogEntry(
                id: MemoryModule.descriptor.id,
                name: MemoryModule.descriptor.name,
                summary: MemoryModule.descriptor.summary,
                requiresConnection: false, settings: []),
            CatalogEntry(
                id: BatteryModule.descriptor.id,
                name: BatteryModule.descriptor.name,
                summary: BatteryModule.descriptor.summary,
                requiresConnection: false, settings: []),
            CatalogEntry(
                id: TimerModule.descriptor.id,
                name: TimerModule.descriptor.name,
                summary: TimerModule.descriptor.summary,
                requiresConnection: false,
                settings: [
                    ModuleSetting(key: "minutes", label: "Minutes", placeholder: "25", defaultValue: "25"),
                ]),
            CatalogEntry(
                id: ClockModule.descriptor.id,
                name: ClockModule.descriptor.name,
                summary: ClockModule.descriptor.summary,
                requiresConnection: false, settings: []),
        ]
    }

    /// Look up one entry by module id.
    public static func entry(id: String) -> CatalogEntry? {
        all().first { $0.id == id }
    }
}
