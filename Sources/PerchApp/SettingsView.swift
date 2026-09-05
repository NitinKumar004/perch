import SwiftUI
import PerchConfig
import PerchModules

/// A native settings window: choose which module sits in each slot and fill its
/// settings — no JSON. It edits the active preset of the loaded config and hands
/// the result back through `onSave`, which persists it and re-wires the notch.
struct SettingsView: View {
    @State private var left: SlotEditor
    @State private var right: SlotEditor
    private let presetName: String
    private let baseConfig: LayoutConfig
    private let onSave: (LayoutConfig) -> Void

    private let catalog = ModuleCatalog.all()

    init(config: LayoutConfig, onSave: @escaping (LayoutConfig) -> Void) {
        self.baseConfig = config
        self.onSave = onSave
        let preset = config.current ?? Preset()
        self.presetName = config.activePreset
        _left = State(initialValue: SlotEditor(binding: preset.leftPill))
        _right = State(initialValue: SlotEditor(binding: preset.rightPill))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    slotSection(title: "Left pill", editor: $left)
                    Divider()
                    slotSection(title: "Right pill", editor: $right)
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Perch Settings").font(.system(size: 16, weight: .semibold))
            Text("Preset: \(presetName) · choose what each pill shows")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func slotSection(title: String, editor: Binding<SlotEditor>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))

            Picker("Module", selection: editor.moduleID) {
                Text("— none —").tag("")
                ForEach(catalog) { entry in
                    Text(entry.name).tag(entry.id)
                }
            }
            .labelsHidden()

            if let entry = catalog.first(where: { $0.id == editor.wrappedValue.moduleID }) {
                Text(entry.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(entry.settings, id: \.key) { setting in
                    HStack {
                        Text(setting.label).font(.system(size: 12)).frame(width: 130, alignment: .leading)
                        TextField(setting.placeholder, text: editor.setting(setting.key, default: setting.defaultValue))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func save() {
        var config = baseConfig
        var preset = config.current ?? Preset()
        preset.leftPill = left.toBinding()
        preset.rightPill = right.toBinding()
        config.presets[config.activePreset] = preset
        onSave(config)
    }
}

/// Editable state for one slot: the chosen module id and its settings.
private struct SlotEditor {
    var moduleID: String
    var settings: [String: String]

    init(binding: SlotBinding?) {
        moduleID = binding?.module ?? ""
        settings = binding?.settings ?? [:]
    }

    func toBinding() -> SlotBinding? {
        guard !moduleID.isEmpty else { return nil }
        return SlotBinding(module: moduleID, settings: settings.filter { !$0.value.isEmpty })
    }
}

private extension Binding where Value == SlotEditor {
    var moduleID: Binding<String> {
        Binding<String>(get: { wrappedValue.moduleID }, set: { wrappedValue.moduleID = $0 })
    }
    func setting(_ key: String, default defaultValue: String) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue.settings[key] ?? defaultValue },
            set: { wrappedValue.settings[key] = $0 }
        )
    }
}
