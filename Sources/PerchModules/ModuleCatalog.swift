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

/// One entry in the catalog: a module's identity, its picker grouping/tag, and
/// the settings it exposes. Built from a module's own `ModuleDescriptor` in
/// `ModuleSpecs`, so this never re-declares truth that lives on the descriptor.
public struct CatalogEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let requiresConnection: Bool
    /// Which picker group this module belongs to — declared, not inferred.
    public let category: ModuleCategory
    /// A short one-liner shown after the name in the picker ("usage %"). Empty
    /// for modules that need none.
    public let tag: String
    public let settings: [ModuleSetting]

    public init(id: String, name: String, summary: String, requiresConnection: Bool,
                category: ModuleCategory, tag: String, settings: [ModuleSetting]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.requiresConnection = requiresConnection
        self.category = category
        self.tag = tag
        self.settings = settings
    }

    /// The picker label: "Name  ·  tag", or just the name when there's no tag.
    public var pickerLabel: String {
        tag.isEmpty ? name : "\(name)  ·  \(tag)"
    }
}

/// The list of every user-pickable module, with the settings each accepts —
/// derived from the single `ModuleSpecs` registry so it can never drift from the
/// factory. Add a module in `ModuleSpecs.all` and it appears here automatically.
public enum ModuleCatalog {
    public static func all() -> [CatalogEntry] {
        ModuleSpecs.all.filter { !$0.hidden }.map(\.entry)
    }

    /// Look up one entry by module id (hidden modules included, so a config that
    /// references one still resolves its settings).
    public static func entry(id: String) -> CatalogEntry? {
        ModuleSpecs.spec(id: id)?.entry
    }
}
