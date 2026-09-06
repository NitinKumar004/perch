import Testing
@testable import PerchApp
import PerchModules

@MainActor
@Test func pickerLabelIsNameWithShortTag() {
    let thermal = ModuleCatalog.entry(id: "system.thermal")!
    #expect(SettingsView.pickerLabel(for: thermal) == "Thermal  ·  heat warning")

    let cpu = ModuleCatalog.entry(id: "system.cpu")!
    #expect(SettingsView.pickerLabel(for: cpu) == "CPU  ·  usage %")

    // Every catalog module gets a tag (none fall through to bare name).
    for entry in ModuleCatalog.all() {
        #expect(SettingsView.pickerLabel(for: entry).contains(" · "),
                "no picker tag for \(entry.id)")
    }
}
