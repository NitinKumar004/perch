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
    public static let currentVersion = 2

    public var schemaVersion: Int
    /// The preset shown right now. Must be a key in `presets`.
    public var activePreset: String
    /// Named layouts the user can switch between.
    public var presets: [String: Preset]
    /// Where the HUD sits: "flank" (default), "right", or "below".
    public var hudPosition: String
    /// App-wide behaviour that isn't tied to any one module.
    public var global: GlobalSettings

    public init(schemaVersion: Int = LayoutConfig.currentVersion,
                activePreset: String,
                presets: [String: Preset],
                hudPosition: String = "flank",
                global: GlobalSettings = GlobalSettings()) {
        self.schemaVersion = schemaVersion
        self.activePreset = activePreset
        self.presets = presets
        self.hudPosition = hudPosition
        self.global = global
    }

    // Decode with defaults so older config files (no hudPosition / global) load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A file with no schemaVersion is a pre-versioning (v1) file — treat it
        // as v1 so it MIGRATES, rather than throwing (which would be read as
        // corruption and wipe the user's presets).
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        activePreset = try c.decode(String.self, forKey: .activePreset)
        presets = try c.decode([String: Preset].self, forKey: .presets)
        hudPosition = try c.decodeIfPresent(String.self, forKey: .hudPosition) ?? "flank"
        global = try c.decodeIfPresent(GlobalSettings.self, forKey: .global) ?? GlobalSettings()
    }

    /// The preset currently in effect, falling back to the first preset by name
    /// if the named one is missing (deterministic — dictionary order isn't — so
    /// a hand-edited file can't leave the app with nothing, or pick at random).
    public var current: Preset? {
        presets[activePreset] ?? presets.keys.sorted().first.flatMap { presets[$0] }
    }
}

/// App-wide behaviour, independent of any module or preset.
public struct GlobalSettings: Codable, Equatable, Sendable {
    /// Pop the detail panel automatically when a module goes critical (a build
    /// or deploy turns red), so a failure never sits unseen.
    public var autoOpenOnRed: Bool
    /// A "HH:MM-HH:MM" window during which notifications are suppressed, or nil
    /// for none. May wrap past midnight (e.g. "22:00-08:00").
    public var quietHours: String?
    /// The selected colour theme, stored as an opaque id (e.g. "midnight"). The
    /// UI layer maps it to a palette; config stays a lower layer and never knows
    /// the concrete colours. Defaults to "system" (the original look).
    public var theme: String
    /// Whether alerts also show as a transient banner in the notch (in addition
    /// to the macOS notification). Defaults on.
    public var notchBanner: Bool
    /// User-tunable warn/critical levels for the system metrics (CPU, memory,
    /// swap, disk, load). Defaults to sensible standard levels.
    public var thresholds: MetricThresholds
    /// How eagerly a red metric may pop the panel/banner — dwell + cooldown that
    /// damp a value flapping at its threshold. Defaults to sensible pacing.
    public var pacing: AlertPacing

    public init(autoOpenOnRed: Bool = false, quietHours: String? = nil,
                theme: String = "system", notchBanner: Bool = true,
                thresholds: MetricThresholds = .standard,
                pacing: AlertPacing = .standard) {
        self.autoOpenOnRed = autoOpenOnRed
        self.quietHours = quietHours
        self.theme = theme
        self.notchBanner = notchBanner
        self.thresholds = thresholds
        self.pacing = pacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoOpenOnRed = try c.decodeIfPresent(Bool.self, forKey: .autoOpenOnRed) ?? false
        quietHours = try c.decodeIfPresent(String.self, forKey: .quietHours)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        notchBanner = try c.decodeIfPresent(Bool.self, forKey: .notchBanner) ?? true
        thresholds = try c.decodeIfPresent(MetricThresholds.self, forKey: .thresholds) ?? .standard
        pacing = try c.decodeIfPresent(AlertPacing.self, forKey: .pacing) ?? .standard
    }

    /// Parse `quietHours` into (startMinuteOfDay, endMinuteOfDay), or nil if
    /// unset/malformed. Both are 0…1439; the window wraps when start > end.
    public var quietWindow: (start: Int, end: Int)? {
        guard let quietHours else { return nil }
        let ends = quietHours.split(separator: "-", maxSplits: 1).map(String.init)
        guard ends.count == 2,
              let start = GlobalSettings.minuteOfDay(ends[0]),
              let end = GlobalSettings.minuteOfDay(ends[1]) else { return nil }
        return (start, end)
    }

    /// Is `minute` (0…1439) inside the quiet window? Handles the midnight wrap.
    public func isQuiet(minuteOfDay minute: Int) -> Bool {
        guard let w = quietWindow else { return false }
        if w.start == w.end { return false }                 // empty window
        return w.start < w.end
            ? (minute >= w.start && minute < w.end)          // same-day window
            : (minute >= w.start || minute < w.end)          // wraps midnight
    }

    static func minuteOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
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

    /// Return a tidied copy of the layout:
    /// - the **panel** drops only *identical* rows — same module AND same settings.
    ///   The same module type with different settings is a distinct instance and
    ///   is kept (e.g. Pull requests for two different repos).
    /// - the **right pill is cleared only if it's identical to the left** (same
    ///   module and settings) — redundant. Two same-type-but-differently-configured
    ///   pills are allowed.
    ///
    /// A pill may hold a module that is also in the panel — that's intended.
    public func normalizedSlots() -> Preset {
        var seen = Set<SlotBinding>()
        let dedupedPanel = panel.filter { seen.insert($0).inserted }
        var right = rightPill
        if let left = leftPill, right == left { right = nil }
        return Preset(leftPill: leftPill, rightPill: right, panel: dedupedPanel)
    }
}

/// A module placed in a slot, plus the settings that module needs. Settings are
/// free-form strings so each module owns its own keys without the config type
/// having to know them.
public struct SlotBinding: Codable, Equatable, Hashable, Sendable {
    /// The module's stable id, e.g. `"github.builds"`.
    public var module: String
    /// Module-specific settings, e.g. `["repo": "owner/name", "branch": "main"]`.
    public var settings: [String: String]

    public init(module: String, settings: [String: String] = [:]) {
        self.module = module
        self.settings = settings
    }
}
