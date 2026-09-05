import Foundation
import PerchCore

/// A user-facing description of a setting a module accepts, so a settings UI can
/// render the right field without hard-coding any module's keys.
public struct ModuleSetting: Sendable, Equatable {
    public let key: String
    public let label: String
    public let placeholder: String
    public let defaultValue: String

    public init(key: String, label: String, placeholder: String, defaultValue: String = "") {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.defaultValue = defaultValue
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
                    ModuleSetting(key: "queue", label: "Queue", placeholder: "review-requested | author",
                                  defaultValue: "review-requested"),
                    ModuleSetting(key: "repo", label: "Repository (optional)", placeholder: "owner/name"),
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
