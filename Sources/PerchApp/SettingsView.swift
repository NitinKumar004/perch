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
    @State private var autoOpenOnRed: Bool
    @State private var quietHours: String
    @State private var config: LayoutConfig       // the whole layout being edited
    @State private var activePreset: String       // the preset key currently shown
    @State private var presetNameField: String    // editable name of the active preset

    private let onSave: (LayoutConfig) -> Void
    private let isConnected: () async -> Bool
    private let onConnect: () -> Void
    private let onUseToken: (String) -> Void
    private let onUseCLI: () -> Void
    private let onDisconnect: () -> Void

    private let catalog = ModuleCatalog.all()

    init(
        config: LayoutConfig,
        isConnected: @escaping () async -> Bool = { false },
        onConnect: @escaping () -> Void = {},
        onUseToken: @escaping (String) -> Void = { _ in },
        onUseCLI: @escaping () -> Void = {},
        onDisconnect: @escaping () -> Void = {},
        onSave: @escaping (LayoutConfig) -> Void
    ) {
        self.onSave = onSave
        self.isConnected = isConnected
        self.onConnect = onConnect
        self.onUseToken = onUseToken
        self.onUseCLI = onUseCLI
        self.onDisconnect = onDisconnect
        // Pick a valid active preset key (fall back to the first if the named one
        // is missing), so the editor always has something to show.
        let activeKey = config.presets[config.activePreset] != nil
            ? config.activePreset : (config.presets.keys.sorted().first ?? "default")
        let preset = config.presets[activeKey] ?? Preset()
        _config = State(initialValue: config)
        _activePreset = State(initialValue: activeKey)
        _presetNameField = State(initialValue: activeKey)
        _left = State(initialValue: SlotEditor(binding: preset.leftPill))
        _right = State(initialValue: SlotEditor(binding: preset.rightPill))
        _panel = State(initialValue: preset.panel.map(SlotEditor.init(binding:)))
        _hudPosition = State(initialValue: config.hudPosition)
        _autoOpenOnRed = State(initialValue: config.global.autoOpenOnRed)
        _quietHours = State(initialValue: config.global.quietHours ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    presetSection
                    Divider()
                    connectionCard
                    Divider()
                    positionSection
                    Divider()
                    behaviourSection
                    Divider()
                    slotSection(title: "Left pill",
                                caption: "The icon just left of the notch.",
                                editor: $left, kind: .left)
                    Divider()
                    slotSection(title: "Right pill",
                                caption: "The icon just right of the notch.",
                                editor: $right, kind: .right)
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
            Text("Pick what each spot shows. Editing preset: \(activePreset)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    // MARK: - Presets (named layouts)

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preset").font(.system(size: 13, weight: .semibold))
            Text("A named layout you can switch between. Switching keeps each preset's edits.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { activePreset },
                                              set: { switchPreset(to: $0) })) {
                    ForEach(config.presets.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 150)
                Button { newPreset() } label: { Label("New", systemImage: "plus") }
                    .controlSize(.small)
                Button(role: .destructive) { deletePreset() } label: { Image(systemName: "trash") }
                    .controlSize(.small).disabled(config.presets.count <= 1)
                    .help("Delete this preset")
            }
            HStack(spacing: 8) {
                Text("Name").font(.system(size: 12)).frame(width: 44, alignment: .leading)
                TextField("preset name", text: $presetNameField)
                    .textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit { renameActivePreset(to: presetNameField) }
                Text("↩ to rename").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
    }

    /// Save the on-screen editors back into the current preset before any switch.
    private func commitEditors() {
        var preset = config.presets[activePreset] ?? Preset()
        preset.leftPill = left.toBinding()
        preset.rightPill = right.toBinding()
        preset.panel = panel.compactMap { $0.toBinding() }
        config.presets[activePreset] = preset.normalizedSlots()
    }

    /// Load a preset's slots into the editors.
    private func loadEditors(from key: String) {
        let preset = config.presets[key] ?? Preset()
        left = SlotEditor(binding: preset.leftPill)
        right = SlotEditor(binding: preset.rightPill)
        panel = preset.panel.map(SlotEditor.init(binding:))
        presetNameField = key
    }

    private func switchPreset(to key: String) {
        guard key != activePreset else { return }
        commitEditors()
        activePreset = key
        loadEditors(from: key)
    }

    private func newPreset() {
        commitEditors()
        var name = "layout"; var n = 2
        while config.presets[name] != nil { name = "layout \(n)"; n += 1 }
        config.presets[name] = Preset()
        activePreset = name
        loadEditors(from: name)
    }

    private func deletePreset() {
        guard config.presets.count > 1 else { return }
        config.presets[activePreset] = nil
        let next = config.presets.keys.sorted().first ?? "default"
        activePreset = next
        loadEditors(from: next)
    }

    private func renameActivePreset(to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != activePreset, config.presets[name] == nil else {
            presetNameField = activePreset   // revert an invalid/duplicate name
            return
        }
        commitEditors()
        let preset = config.presets[activePreset]
        config.presets[activePreset] = nil
        config.presets[name] = preset
        activePreset = name
        presetNameField = name
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

    // MARK: - Behaviour

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Behaviour").font(.system(size: 13, weight: .semibold))
            Toggle("Open the panel automatically when something goes red",
                   isOn: $autoOpenOnRed)
                .toggleStyle(.checkbox).font(.system(size: 12))
            HStack(spacing: 8) {
                Text("Quiet hours").font(.system(size: 12)).frame(width: 90, alignment: .leading)
                TextField("22:00-08:00", text: $quietHours)
                    .textFieldStyle(.roundedBorder).frame(width: 130)
                Text("no notifications in this window").font(.system(size: 11)).foregroundStyle(.secondary)
            }
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
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Connected").font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                        Button("Disconnect") { onDisconnect(); connected = false }
                            .controlSize(.small)
                    }
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

    private func slotSection(title: String, caption: String, editor: Binding<SlotEditor>, kind: SlotKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            modulePicker(editor: editor, kind: kind)
            settingsFields(for: editor)
        }
    }

    /// Which slot a picker is for — used to hide only the modules that would
    /// truly clash. Pills only exclude *each other* (so left ≠ right); a panel
    /// row only excludes the *other* panel rows. A module in the panel can still
    /// be pinned to a pill — that overlap is allowed.
    private enum SlotKind: Equatable { case left, right, panel(Int) }

    private func clashingModuleIDs(for kind: SlotKind) -> Set<String> {
        switch kind {
        case .left:  return right.moduleID.isEmpty ? [] : [right.moduleID]
        case .right: return left.moduleID.isEmpty ? [] : [left.moduleID]
        case .panel(let index):
            var ids = Set<String>()
            for (j, editor) in panel.enumerated() where j != index && !editor.moduleID.isEmpty {
                ids.insert(editor.moduleID)
            }
            return ids
        }
    }

    /// Where a clashing module is already placed — so a disabled item can explain
    /// itself ("in the right pill") instead of just vanishing from the list.
    private func inUseReason(_ id: String, for kind: SlotKind) -> String {
        switch kind {
        case .left:  return "in right pill"
        case .right: return "in left pill"
        case .panel: return "already in the panel"
        }
    }

    /// A module picker whose choices are grouped by what they need, so the
    /// local-vs-GitHub distinction is obvious *before* you pick. Only modules
    /// that would genuinely clash for this slot are hidden (see `SlotKind`).
    private func modulePicker(editor: Binding<SlotEditor>, kind: SlotKind) -> some View {
        let taken = clashingModuleIDs(for: kind).subtracting([editor.wrappedValue.moduleID])
        let selected = catalog.first { $0.id == editor.wrappedValue.moduleID }
        // A Menu (not a Picker) so the closed control shows only the chosen name,
        // while each item explains itself — "Name — what it does" — so you know
        // what you're picking before you pick it.
        return Menu {
            Button("— none —") { editor.wrappedValue.moduleID = "" }
            ForEach(ModuleGroup.allCases, id: \.self) { group in
                let entries = catalog.filter { self.group(for: $0) == group }
                if !entries.isEmpty {
                    Section(group.label) {
                        ForEach(entries) { entry in
                            // Show every module. A clashing one stays visible but
                            // disabled, with a note saying where it already lives —
                            // so it never looks "missing".
                            if taken.contains(entry.id) {
                                Button("\(Self.pickerLabel(for: entry))  (\(inUseReason(entry.id, for: kind)))") {}
                                    .disabled(true)
                            } else {
                                Button(Self.pickerLabel(for: entry)) {
                                    editor.wrappedValue.moduleID = entry.id
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(selected?.name ?? "— none —")
                    .foregroundStyle(selected == nil ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
    }

    /// A compact "Name — short tag" for a menu item: scannable, never a full
    /// sentence. The full summary still shows below the picker once selected.
    static func pickerLabel(for entry: CatalogEntry) -> String {
        let tag: String
        switch entry.id {
        case "system.cpu":          tag = "usage %"
        case "system.memory":       tag = "RAM in use"
        case "system.network":      tag = "up / down"
        case "system.thermal":      tag = "heat warning"
        case "system.swap":         tag = "thrash warning"
        case "system.load":         tag = "system load"
        case "system.disk":         tag = "free space"
        case "system.clipboard":    tag = "recent copies"
        case "system.fileshelf":    tag = "stash files"
        case "system.port":         tag = "port up?"
        case "system.battery":      tag = "charge %"
        case "focus.timer":         tag = "pomodoro"
        case "system.calendar":     tag = "next meeting"
        case "system.clock":        tag = "the time"
        case "github.builds":       tag = "one repo's CI"
        case "github.builds.multi": tag = "many repos' CI"
        case "github.prs":          tag = "review queue"
        case "deploy.health":       tag = "URL up / down"
        default:                    tag = ""
        }
        return tag.isEmpty ? entry.name : "\(entry.name)  ·  \(tag)"
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
                    if setting.kind == .toggle {
                        Toggle(setting.label, isOn: editor.boolSetting(setting.key, default: setting.defaultValue == "true"))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    } else if let options = setting.options {
                        Text(setting.label).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                        // Fixed choices → a dropdown, so nothing has to be typed.
                        Picker("", selection: editor.setting(setting.key, default: setting.defaultValue)) {
                            ForEach(options, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(setting.label).font(.system(size: 12)).frame(width: 150, alignment: .leading)
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
                        modulePicker(editor: $panel[i], kind: .panel(i))
                        // Pin this panel module to a pill — it stays in the panel
                        // and replaces whatever that pill held.
                        Menu {
                            Button("Move to left pill")  { promote(i, toLeft: true) }
                            Button("Move to right pill") { promote(i, toLeft: false) }
                        } label: { Image(systemName: "arrow.up.forward.square") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .controlSize(.small).disabled(panel[i].moduleID.isEmpty)
                            .help("Move this module into the left or right pill")
                        // Reorder: move this row up / down in the panel stack.
                        Button { move(from: i, to: i - 1) } label: { Image(systemName: "chevron.up") }
                            .controlSize(.small).disabled(i == 0)
                        Button { move(from: i, to: i + 1) } label: { Image(systemName: "chevron.down") }
                            .controlSize(.small).disabled(i == panel.count - 1)
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

    /// Swap a panel row to a new index, clamped so the buttons can't over-run.
    private func move(from: Int, to: Int) {
        guard panel.indices.contains(from), to >= 0, to < panel.count else { return }
        let item = panel.remove(at: from)
        panel.insert(item, at: to)
    }

    /// Pin a panel module (with its settings) to the left or right pill. It stays
    /// in the panel — the pill is an additional place it shows — and replaces
    /// whatever that pill held. If the other pill already holds this same module,
    /// that pill is cleared so a module is never pinned to both pills.
    private func promote(_ index: Int, toLeft: Bool) {
        guard panel.indices.contains(index) else { return }
        let item = panel[index]   // copy — the panel row stays put
        if toLeft {
            left = item
            if right.moduleID == item.moduleID { right = SlotEditor(binding: nil) }
        } else {
            right = item
            if left.moduleID == item.moduleID { left = SlotEditor(binding: nil) }
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
        commitEditors()   // fold the on-screen slots into the active preset
        var out = config
        out.activePreset = activePreset
        out.hudPosition = hudPosition
        let trimmed = quietHours.trimmingCharacters(in: .whitespaces)
        out.global = GlobalSettings(autoOpenOnRed: autoOpenOnRed,
                                    quietHours: trimmed.isEmpty ? nil : trimmed)
        onSave(out)
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
    func boolSetting(_ key: String, default defaultValue: Bool) -> Binding<Bool> {
        Binding<Bool>(
            get: { (wrappedValue.settings[key] ?? (defaultValue ? "true" : "false")) == "true" },
            set: { wrappedValue.settings[key] = $0 ? "true" : "false" }
        )
    }
}
