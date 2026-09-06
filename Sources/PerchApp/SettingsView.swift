import SwiftUI
import PerchConfig
import PerchModules

/// A native settings window: choose which module sits in each slot — left pill,
/// right pill, and the drop-down panel (a list) — and fill each one's settings.
///
/// The mental model is made explicit for newcomers: a connection card up top
/// makes GitHub sign-in a one-click affair, and every module picker groups its
/// choices by what they need — "On your Mac" (instant), "GitHub" (live, needs
/// sign-in) and "Web check" (a URL). No JSON. Edits the active preset and hands
/// the result to `onSave`, which persists it and re-wires the notch.
struct SettingsView: View {
    @State private var left: SlotEditor
    @State private var right: SlotEditor
    @State private var panel: [SlotEditor]
    @State private var connected: Bool?   // nil = still checking
    @State private var showTokenField = false
    @State private var tokenText = ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var hudPosition: String

    private let presetName: String
    private let baseConfig: LayoutConfig
    private let onSave: (LayoutConfig) -> Void
    private let isConnected: () async -> Bool
    private let onConnect: () -> Void
    private let onUseToken: (String) -> Void
    private let onUseCLI: () -> Void

    private let catalog = ModuleCatalog.all()

    init(
        config: LayoutConfig,
        isConnected: @escaping () async -> Bool = { false },
        onConnect: @escaping () -> Void = {},
        onUseToken: @escaping (String) -> Void = { _ in },
        onUseCLI: @escaping () -> Void = {},
        onSave: @escaping (LayoutConfig) -> Void
    ) {
        self.baseConfig = config
        self.onSave = onSave
        self.isConnected = isConnected
        self.onConnect = onConnect
        self.onUseToken = onUseToken
        self.onUseCLI = onUseCLI
        let preset = config.current ?? Preset()
        self.presetName = config.activePreset
        _left = State(initialValue: SlotEditor(binding: preset.leftPill))
        _right = State(initialValue: SlotEditor(binding: preset.rightPill))
        _panel = State(initialValue: preset.panel.map(SlotEditor.init(binding:)))
        _hudPosition = State(initialValue: config.hudPosition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionCard
                    Divider()
                    positionSection
                    Divider()
                    slotSection(title: "Left pill",
                                caption: "The icon just left of the notch.",
                                editor: $left)
                    Divider()
                    slotSection(title: "Right pill",
                                caption: "The icon just right of the notch.",
                                editor: $right)
                    Divider()
                    panelSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 500, height: 640)
        .task {
            // Load once, then keep the card in sync while the window is open so it
            // flips to "Connected" on its own right after the device-flow login.
            while !Task.isCancelled {
                connected = await isConnected()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Perch Settings").font(.system(size: 16, weight: .semibold))
            Text("Pick what each spot shows. Preset: \(presetName)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    // MARK: - HUD position

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HUD position").font(.system(size: 13, weight: .semibold))
            Picker("", selection: $hudPosition) {
                Text("Flank the notch").tag("flank")
                Text("Right of the notch").tag("right")
                Text("Below the menu bar").tag("below")
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Use “Right of the notch” if the pills overlap your menus; “Below” suits non-notch displays.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: - GitHub connection

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: connected == true ? "checkmark.seal.fill" : "person.badge.key")
                    .font(.system(size: 20))
                    .foregroundStyle(connected == true ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub").font(.system(size: 13, weight: .semibold))
                    Text(connectionSubtitle)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                switch connected {
                case .some(true):
                    Text("Connected").font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                case .some(false):
                    VStack(alignment: .trailing, spacing: 4) {
                        // One-click: reuse the gh CLI login (sees private repos).
                        Button("Use GitHub CLI") { onUseCLI() }.controlSize(.regular)
                        Button("Connect with browser") { onConnect() }.controlSize(.small)
                    }
                case .none:
                    ProgressView().controlSize(.small)
                }
            }

            // Token sign-in — the path that reads private org repos without an
            // app install. Collapsed by default so the simple path stays simple.
            DisclosureGroup(isExpanded: $showTokenField) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reads every repo you can access — including private org repos the app isn't installed on. Create a token with `repo` (classic) or read-only Contents + Pull requests (fine-grained).")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    HStack {
                        SecureField("ghp_… or github_pat_…", text: $tokenText)
                            .textFieldStyle(.roundedBorder)
                        Button("Use token") { onUseToken(tokenText); tokenText = "" }
                            .disabled(tokenText.isEmpty)
                    }
                    Link("Create a token on GitHub ↗",
                         destination: URL(string: "https://github.com/settings/tokens?type=beta")!)
                        .font(.system(size: 10.5))
                }
                .padding(.top, 4)
            } label: {
                Text("Sign in with a token instead").font(.system(size: 11, weight: .medium))
            }

            // Private-repo help — the #1 confusion. Spell out the two paths.
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signing in with GitHub uses the Perch app, which can only read **private** repos where it's installed. Two ways to see them:")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Label("Install the Perch app on that repo/org (org repos may need an owner's approval).", systemImage: "1.circle")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Label("Or sign in with a token above — it reads every repo you can access.", systemImage: "2.circle")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Link("Manage repo access on GitHub ↗",
                         destination: URL(string: "https://github.com/settings/installations")!)
                        .font(.system(size: 10.5))
                }
                .padding(.top, 4)
            } label: {
                Text("A private repo isn't showing?").font(.system(size: 11, weight: .medium))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
    }

    private var connectionSubtitle: String {
        switch connected {
        case .some(true):  return "Live checks (Build, Pull requests) are enabled."
        case .some(false): return "Sign in once to enable live GitHub checks."
        case .none:        return "Checking…"
        }
    }

    // MARK: - One slot (a single module)

    private func slotSection(title: String, caption: String, editor: Binding<SlotEditor>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            modulePicker(editor: editor)
            settingsFields(for: editor)
        }
    }

    /// A module picker whose choices are grouped by what they need, so the
    /// local-vs-GitHub distinction is obvious *before* you pick.
    private func modulePicker(editor: Binding<SlotEditor>) -> some View {
        Picker("Module", selection: editor.moduleID) {
            Text("— none —").tag("")
            ForEach(ModuleGroup.allCases, id: \.self) { group in
                let entries = catalog.filter { self.group(for: $0) == group }
                if !entries.isEmpty {
                    Section(group.label) {
                        ForEach(entries) { entry in Text(entry.name).tag(entry.id) }
                    }
                }
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private func settingsFields(for editor: Binding<SlotEditor>) -> some View {
        if let entry = catalog.first(where: { $0.id == editor.wrappedValue.moduleID }) {
            let grp = group(for: entry)
            HStack(spacing: 6) {
                Image(systemName: grp.icon).font(.system(size: 10)).foregroundStyle(.secondary)
                Text(grp.label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(entry.summary).font(.system(size: 11)).foregroundStyle(.secondary)

            // If this module needs GitHub and we're not signed in, say so plainly.
            if entry.requiresConnection, connected == false {
                Label("Connect GitHub above to enable this.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }

            ForEach(entry.settings, id: \.key) { setting in
                HStack {
                    Text(setting.label).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                    if let options = setting.options {
                        // Fixed choices → a dropdown, so nothing has to be typed.
                        Picker("", selection: editor.setting(setting.key, default: setting.defaultValue)) {
                            ForEach(options, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField(setting.placeholder,
                                  text: editor.setting(setting.key, default: setting.defaultValue))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    // MARK: - Panel (a list of modules)

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Panel").font(.system(size: 13, weight: .semibold))
                    Text("The list shown when you click the notch.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
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
            if LoginItem.isAvailable {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = $0; LoginItem.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
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
        config.hudPosition = hudPosition
        onSave(config)
    }

    // MARK: - Grouping

    /// How a module is grouped in the picker — derived from what it needs, so
    /// adding a new module to the catalog slots it in automatically.
    private enum ModuleGroup: CaseIterable {
        case local, github, web

        var label: String {
            switch self {
            case .local:  return "On your Mac — no setup"
            case .github: return "GitHub — live, needs sign-in"
            case .web:    return "Web check — a URL"
            }
        }
        var icon: String {
            switch self {
            case .local:  return "desktopcomputer"
            case .github: return "person.badge.key"
            case .web:    return "globe"
            }
        }
    }

    private func group(for entry: CatalogEntry) -> ModuleGroup {
        if entry.requiresConnection { return .github }
        if entry.settings.contains(where: { $0.key == "url" }) { return .web }
        return .local
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
