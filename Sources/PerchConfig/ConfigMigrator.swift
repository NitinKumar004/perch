import Foundation

/// Migrates an on-disk config forward to the current schema version.
///
/// Each version bump adds a step here; a config is migrated one version at a
/// time until it reaches `LayoutConfig.currentVersion`. Today there is only v1,
/// so this is a pass-through — but the mechanism exists from day one so a future
/// change never breaks an existing user's file.
public enum ConfigMigrator {
    /// Migrate a decoded config to the current version. Returns the possibly
    /// upgraded config and whether anything changed (so the caller can re-save).
    public static func migrate(_ config: LayoutConfig) -> (config: LayoutConfig, changed: Bool) {
        var current = config
        var changed = false

        while current.schemaVersion < LayoutConfig.currentVersion {
            switch current.schemaVersion {
            // case 1: current = migrateV1toV2(current)
            default:
                // Unknown older version we don't have a step for: stamp it to the
                // current version rather than looping forever.
                current.schemaVersion = LayoutConfig.currentVersion
            }
            changed = true
        }
        return (current, changed)
    }
}
