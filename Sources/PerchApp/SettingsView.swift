import SwiftUI
import PerchConfig
import PerchModules

/// A native settings window: choose which module sits in each slot — left pill,
/// right pill, and the drop-down panel (a list) — and fill each one's settings.
/// No JSON. Edits the active preset and hands the result to `onSave`, which
/// persists it and re-wires the notch.
struct SettingsView: View {
    @State private var left: SlotEditor
    @State private var right: SlotEditor
    @State private var panel: [SlotEditor]
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
        _panel = State(initialValue: preset.panel.map(SlotEditor.init(binding:)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    slotSection(title: "Left pill", editor: $left)
                    Divider()
                    slotSection(title: "Right pill", editor: $right)
                    Divider()
                    panelSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 600)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Perch Settings").font(.system(size: 16, weight: .semibold))
            Text("Preset: \(presetName) · choose what each pill and the panel show")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    // MARK: - One slot (a single module)

    private func slotSection(title: String, editor: Binding<SlotEditor>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            modulePicker(editor: editor)
            settingsFields(for: editor)
        }
    }

    private func modulePicker(editor: Binding<SlotEditor>) -> some View {
        Picker("Module", selection: editor.moduleID) {
            Text("— none —").tag("")
            ForEach(catalog) { entry in Text(entry.name).tag(entry.id) }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private func settingsFields(for editor: Binding<SlotEditor>) -> some View {
        if let entry = catalog.first(where: { $0.id == editor.wrappedValue.moduleID }) {
            HStack(spacing: 6) {
                Image(systemName: entry.requiresConnection ? "person.badge.key" : "desktopcomputer")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(entry.requiresConnection ? "Needs GitHub" : "Local — no setup")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(entry.summary).font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(entry.settings, id: \.key) { setting in
                HStack {
                    Text(setting.label).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                    TextField(setting.placeholder,
                              text: editor.setting(setting.key, default: setting.defaultValue))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Panel (a list of modules)

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Panel (drop-down)").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    panel.append(SlotEditor(binding: nil))
                } label: { Label("Add", systemImage: "plus") }
                    .controlSize(.small)
            }
            if panel.isEmpty {
                Text("Nothing in the panel yet — add a module.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(panel.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        modulePicker(editor: $panel[i])
                        Button(role: .destructive) {
                            panel.remove(at: i)
                        } label: { Image(systemName: "trash") }
                            .controlSize(.small)
                    }
                    settingsFields(for: $panel[i])
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Save") { save() }.keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func save() {
        var config = baseConfig
        var preset = config.current ?? Preset()
        preset.leftPill = left.toBinding()
        preset.rightPill = right.toBinding()
        preset.panel = panel.compactMap { $0.toBinding() }
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
        // Keep only settings that belong to the chosen module, dropping leftovers
        // from a previous selection and any empty values.
        let keys = Set(ModuleCatalog.entry(id: moduleID)?.settings.map(\.key) ?? [])
        let scoped = settings.filter { keys.contains($0.key) && !$0.value.isEmpty }
        return SlotBinding(module: moduleID, settings: scoped)
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
