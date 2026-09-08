import Foundation

/// The one place Perch's on-disk locations are defined, so config, run-history
/// and any future local store all derive from the same directory instead of each
/// re-building `~/.config/perch/…`.
public enum PerchPaths {
    /// `~/.config/perch` — Perch's per-user data directory.
    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("perch", isDirectory: true)
    }

    /// A file inside the config directory (e.g. `layout.json`, `run-history.json`).
    public static func configFile(_ name: String) -> URL {
        configDirectory.appendingPathComponent(name)
    }
}
