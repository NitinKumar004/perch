import Foundation
import PerchCore

/// The user's entire configuration, as persisted in `layout.json`.
///
/// This is the single source of "what the user wants": which sources to watch,
/// which module sits in which slot, each module's settings, and named presets.
/// It is `Codable` so it round-trips to disk, and versioned so the app can
/// migrate an old file forward instead of breaking on it.
public struct LayoutConfig: Codable, Equatable, Sendable {
    /// The current on-disk schema version. Bump when the shape changes and add
    /// a migration in `ConfigMigrator`.
    public static let currentVersion = 1

    public var schemaVersion: Int
    /// The preset shown right now. Must be a key in `presets`.
    public var activePreset: String
    /// Named layouts the user can switch between.
    public var presets: [String: Preset]

    public init(schemaVersion: Int = LayoutConfig.currentVersion,
                activePreset: String,
                presets: [String: Preset]) {
        self.schemaVersion = schemaVersion
        self.activePreset = activePreset
        self.presets = presets
    }

    /// The preset currently in effect, falling back to the first preset by name
    /// if the named one is missing (deterministic — dictionary order isn't — so
    /// a hand-edited file can't leave the app with nothing, or pick at random).
    public var current: Preset? {
        presets[activePreset] ?? presets.keys.sorted().first.flatMap { presets[$0] }
    }
}

/// One named layout: what occupies each slot.
public struct Preset: Codable, Equatable, Sendable {
    /// A single glanceable module, or nil to leave the slot empty.
    public var leftPill: SlotBinding?
    public var rightPill: SlotBinding?
    /// A stack of modules shown in the drop-down panel, top to bottom.
    public var panel: [SlotBinding]

    public init(leftPill: SlotBinding? = nil,
                rightPill: SlotBinding? = nil,
                panel: [SlotBinding] = []) {
        self.leftPill = leftPill
        self.rightPill = rightPill
        self.panel = panel
    }
}

/// A module placed in a slot, plus the settings that module needs. Settings are
/// free-form strings so each module owns its own keys without the config type
/// having to know them.
public struct SlotBinding: Codable, Equatable, Sendable {
    /// The module's stable id, e.g. `"github.builds"`.
    public var module: String
    /// Module-specific settings, e.g. `["repo": "owner/name", "branch": "main"]`.
    public var settings: [String: String]

    public init(module: String, settings: [String: String] = [:]) {
        self.module = module
        self.settings = settings
    }
}
