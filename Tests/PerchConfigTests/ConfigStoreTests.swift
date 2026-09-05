import Testing
import Foundation
@testable import PerchConfig

/// Each test runs against a fresh temp directory so nothing touches the real
/// ~/.config/perch/layout.json.
private func tempConfigURL() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("perch-tests-\(UUID().uuidString)", isDirectory: true)
    return dir.appendingPathComponent("layout.json")
}

@Test func missingFileWritesAndReturnsDefaults() throws {
    let url = tempConfigURL()
    let store = ConfigStore(fileURL: url)

    let config = store.load()

    #expect(config.activePreset == "default")
    #expect(config.presets["default"] != nil)
    // The default was persisted, so a second load reads the same file.
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func roundTripsCustomConfig() throws {
    let url = tempConfigURL()
    let store = ConfigStore(fileURL: url)

    let custom = LayoutConfig(
        activePreset: "work",
        presets: ["work": Preset(
            leftPill: SlotBinding(module: "github.builds", settings: ["repo": "acme/api", "branch": "trunk"]),
            rightPill: SlotBinding(module: "system.clock"),
            panel: [SlotBinding(module: "github.prs", settings: ["filter": "review-requested"])]
        )]
    )
    try store.save(custom)

    let loaded = store.load()
    #expect(loaded == custom)
    #expect(loaded.current?.leftPill?.settings["repo"] == "acme/api")
}

@Test func corruptFileBacksUpAndResets() throws {
    let url = tempConfigURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ this is not valid json".utf8).write(to: url)

    let store = ConfigStore(fileURL: url)
    let config = store.load()

    // Reset to a working default…
    #expect(config.activePreset == "default")
    // …and the bad file was preserved for inspection, not deleted.
    let siblings = try FileManager.default.contentsOfDirectory(
        at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
    #expect(siblings.contains { $0.lastPathComponent.hasPrefix("layout.corrupt.") })
}

@Test func migratorStampsUnknownVersionToCurrent() {
    // A file claiming a version we have no step for is stamped forward, not looped.
    let old = LayoutConfig(schemaVersion: 0, activePreset: "default",
                           presets: ["default": Preset()])
    let (migrated, changed) = ConfigMigrator.migrate(old)
    #expect(migrated.schemaVersion == LayoutConfig.currentVersion)
    #expect(changed)
}

@Test func currentPresetFallsBackWhenActiveMissing() {
    let config = LayoutConfig(activePreset: "nope",
                              presets: ["only": Preset(rightPill: SlotBinding(module: "system.clock"))])
    #expect(config.current?.rightPill?.module == "system.clock")
}
