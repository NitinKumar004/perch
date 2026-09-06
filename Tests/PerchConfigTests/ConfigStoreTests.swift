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

@Test func globalSettingsRoundTripAndDefaultOnOldFile() throws {
    let url = tempConfigURL()
    let store = ConfigStore(fileURL: url)
    var config = LayoutConfig(activePreset: "default", presets: ["default": Preset()])
    config.global = GlobalSettings(autoOpenOnRed: true, quietHours: "22:00-08:00")
    try store.save(config)
    #expect(store.load().global == config.global)

    // A v1-style file with no `global` key still loads with defaults.
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":1,"activePreset":"default","presets":{"default":{"panel":[]}}}"#.utf8).write(to: url)
    let loaded = store.load()
    #expect(loaded.global == GlobalSettings())      // defaulted, not crashed
    #expect(loaded.schemaVersion == LayoutConfig.currentVersion)  // migrated forward
}

@Test func normalizedSlotsAllowsPanelPillOverlapButNotBothPills() {
    // A module pinned to the left pill AND kept in the panel stays in BOTH —
    // that overlap is intentional. Panel duplicates collapse to one.
    let p = Preset(
        leftPill: SlotBinding(module: "system.cpu"),
        rightPill: nil,
        panel: [SlotBinding(module: "system.cpu"), SlotBinding(module: "system.cpu"),
                SlotBinding(module: "system.memory")])
    let n = p.normalizedSlots()
    #expect(n.leftPill?.module == "system.cpu")             // pill kept
    #expect(n.panel.map(\.module) == ["system.cpu", "system.memory"]) // panel deduped, cpu kept
    // The same module can't sit in BOTH pills — the right is cleared.
    let bothPills = Preset(leftPill: SlotBinding(module: "system.clock"),
                           rightPill: SlotBinding(module: "system.clock"))
    #expect(bothPills.normalizedSlots().rightPill == nil)
    #expect(bothPills.normalizedSlots().leftPill?.module == "system.clock")
    // Distinct pills are both preserved.
    let distinct = Preset(leftPill: SlotBinding(module: "system.clock"),
                          rightPill: SlotBinding(module: "github.prs"))
    #expect(distinct.normalizedSlots() == distinct)
}

@Test func quietHoursWindowHandlesMidnightWrap() {
    let wrap = GlobalSettings(quietHours: "22:00-08:00")
    #expect(wrap.isQuiet(minuteOfDay: 23 * 60))       // 23:00 → quiet
    #expect(wrap.isQuiet(minuteOfDay: 2 * 60))        // 02:00 → quiet
    #expect(!wrap.isQuiet(minuteOfDay: 12 * 60))      // noon → loud
    let sameDay = GlobalSettings(quietHours: "09:00-17:00")
    #expect(sameDay.isQuiet(minuteOfDay: 10 * 60))
    #expect(!sameDay.isQuiet(minuteOfDay: 20 * 60))
    // Malformed / empty → never quiet.
    #expect(!GlobalSettings(quietHours: "nonsense").isQuiet(minuteOfDay: 600))
    #expect(!GlobalSettings().isQuiet(minuteOfDay: 600))
}
