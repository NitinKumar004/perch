import Foundation

/// Reads and writes the user's `layout.json`, defensively.
///
/// The guiding rule: **a bad config file must never stop the app from
/// starting.** Missing file → write defaults. Corrupt file → move it aside and
/// start from defaults. Old version → migrate forward. The user always ends up
/// with a working notch.
public struct ConfigStore: Sendable {
    private let fileURL: URL

    /// The process-wide file manager. `FileManager.default` is not `Sendable`,
    /// so we reach for it inside each method rather than storing it.
    private var fileManager: FileManager { .default }

    /// The canonical config location, `~/.config/perch/layout.json`.
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("perch", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    /// - Parameter fileURL: where the config lives. Defaults to
    ///   `~/.config/perch/layout.json`.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ConfigStore.defaultFileURL
    }

    /// Load the config, always returning a usable value.
    ///
    /// - No file: writes and returns the default config.
    /// - Corrupt file: backs it up to `layout.corrupt.<timestamp>.json`, then
    ///   writes and returns the default config.
    /// - Older version: migrates forward and re-saves.
    public func load() -> LayoutConfig {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let fresh = DefaultConfig.make()
            try? save(fresh)
            return fresh
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(LayoutConfig.self, from: data)
            let (migrated, changed) = ConfigMigrator.migrate(decoded)
            if changed { try? save(migrated) }
            return migrated
        } catch {
            // Corrupt/unreadable: preserve the user's file for inspection, then
            // reset to defaults so the app still runs.
            backupCorruptFile()
            let fresh = DefaultConfig.make()
            try? save(fresh)
            return fresh
        }
    }

    /// Persist a config, creating the directory if needed. Pretty-printed with
    /// stable key ordering so the file stays diff-friendly and hand-editable.
    public func save(_ config: LayoutConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    private func backupCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("layout.corrupt.\(stamp).json")
        try? fileManager.moveItem(at: fileURL, to: backup)
    }
}
