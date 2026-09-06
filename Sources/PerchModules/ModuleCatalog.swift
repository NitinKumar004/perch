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

/// How a setting is rendered.
public enum SettingKind: String, Sendable {
    case text     // free-text field
    case choice   // dropdown (uses `options`)
    case toggle   // on/off checkbox (value "true"/"false")
}

/// A user-facing description of a setting a module accepts, so a settings UI can
/// render the right field without hard-coding any module's keys.
public struct ModuleSetting: Sendable, Equatable {
    public let key: String
    public let label: String
    public let placeholder: String
    public let defaultValue: String
    public let options: [SettingOption]?
    public let kind: SettingKind

    public init(key: String, label: String, placeholder: String,
                defaultValue: String = "", options: [SettingOption]? = nil,
                kind: SettingKind = .text) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.options = options
        self.kind = options != nil ? .choice : kind
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
                    Self.refreshSetting(placeholder: "60"),
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
                    ModuleSetting(key: "showChecks", label: "Show CI status", placeholder: "", defaultValue: "true", kind: .toggle),
                    ModuleSetting(key: "showReview", label: "Show review status", placeholder: "", defaultValue: "true", kind: .toggle),
                    ModuleSetting(key: "limit", label: "How many to list", placeholder: "8", defaultValue: "8"),
                    Self.refreshSetting(placeholder: "90"),
                ]),
            CatalogEntry(
                id: MultiBuildsModule.descriptor.id,
                name: MultiBuildsModule.descriptor.name,
                summary: MultiBuildsModule.descriptor.summary,
                requiresConnection: true,
                settings: [
                    ModuleSetting(key: "repos", label: "Repositories", placeholder: "owner/a, owner/b, owner/c"),
                    ModuleSetting(key: "branch", label: "Branch", placeholder: "main", defaultValue: "main"),
                    Self.refreshSetting(placeholder: "90"),
                ]),
            CatalogEntry(
                id: DeployModule.descriptor.id,
                name: DeployModule.descriptor.name,
                summary: DeployModule.descriptor.summary,
                requiresConnection: false,
                settings: [
                    ModuleSetting(key: "url", label: "Health URL", placeholder: "https://example.com/health"),
                    Self.refreshSetting(placeholder: "20"),
                ]),
            CatalogEntry(
                id: VitalsModule.descriptor.id,
                name: VitalsModule.descriptor.name,
                summary: VitalsModule.descriptor.summary,
                requiresConnection: false, settings: [Self.refreshSetting(placeholder: "2")]),
            CatalogEntry(
                id: MemoryModule.descriptor.id,
                name: MemoryModule.descriptor.name,
                summary: MemoryModule.descriptor.summary,
                requiresConnection: false, settings: [Self.refreshSetting(placeholder: "2")]),
            CatalogEntry(
                id: NetworkModule.descriptor.id,
                name: NetworkModule.descriptor.name,
                summary: NetworkModule.descriptor.summary,
                requiresConnection: false, settings: [Self.refreshSetting(placeholder: "2")]),
            CatalogEntry(
                id: ClipboardModule.descriptor.id,
                name: ClipboardModule.descriptor.name,
                summary: ClipboardModule.descriptor.summary,
                requiresConnection: false, settings: []),
            CatalogEntry(
                id: PortMonitorModule.descriptor.id,
                name: PortMonitorModule.descriptor.name,
                summary: PortMonitorModule.descriptor.summary,
                requiresConnection: false,
                settings: [
                    ModuleSetting(key: "port", label: "Port", placeholder: "3000", defaultValue: "3000"),
                    ModuleSetting(key: "label", label: "Label (optional)", placeholder: ":3000"),
                    Self.refreshSetting(placeholder: "5"),
                ]),
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
                requiresConnection: false,
                settings: [
                    ModuleSetting(key: "format", label: "Time format", placeholder: "",
                                  defaultValue: "24",
                                  options: [
                                    SettingOption(value: "24", label: "24-hour (14:30)"),
                                    SettingOption(value: "12", label: "12-hour (2:30 PM)"),
                                  ]),
                    ModuleSetting(key: "showSeconds", label: "Show seconds", placeholder: "",
                                  defaultValue: "false", kind: .toggle),
                ]),
        ]
    }

    /// Look up one entry by module id.
    public static func entry(id: String) -> CatalogEntry? {
        all().first { $0.id == id }
    }

    /// The shared "refresh every N seconds" setting, so any module can offer a
    /// user-tunable poll interval with one line.
    static func refreshSetting(placeholder: String) -> ModuleSetting {
        ModuleSetting(key: "refreshSeconds", label: "Refresh every (sec)", placeholder: placeholder)
    }
}
