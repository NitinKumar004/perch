import SwiftUI
import PerchCore
import PerchConfig
import PerchModules
import PerchNotchUI

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
    @State private var theme: String
    @State private var notchBanner: Bool
    @State private var thresholds: MetricThresholds
    @State private var pacing: AlertPacing
    @State private var expanded: Set<String> = []   // collapsible section ids currently open
    @State private var config: LayoutConfig       // the whole layout being edited
    @State private var activePreset: String       // the preset key currently shown
    @State private var presetNameField: String    // editable name of the active preset

    private let onSave: (LayoutConfig) -> Void
    private let isConnected: () async -> Bool
    private let onConnect: () -> Void
    private let onUseToken: (String) -> Void
    private let onUseCLI: () -> Void
    private let onDisconnect: () -> Void
    /// Shared update state (observed) + the action that checks/installs. Lives in
    /// the header so updates are reachable from Settings, not only the menu bar.
    private let updateModel: NotchViewModel
    private let onCheckUpdate: () -> Void

    private let catalog = ModuleCatalog.all()

    init(
        config: LayoutConfig,
        isConnected: @escaping () async -> Bool = { false },
        onConnect: @escaping () -> Void = {},
        onUseToken: @escaping (String) -> Void = { _ in },
        onUseCLI: @escaping () -> Void = {},
        onDisconnect: @escaping () -> Void = {},
        updateModel: NotchViewModel = NotchViewModel(),
        onCheckUpdate: @escaping () -> Void = {},
        onSave: @escaping (LayoutConfig) -> Void
    ) {
        self.onSave = onSave
        self.isConnected = isConnected
        self.onConnect = onConnect
        self.onUseToken = onUseToken
        self.onUseCLI = onUseCLI
        self.onDisconnect = onDisconnect
        self.updateModel = updateModel
        self.onCheckUpdate = onCheckUpdate
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
        _theme = State(initialValue: config.global.theme)
        _notchBanner = State(initialValue: config.global.notchBanner)
        _thresholds = State(initialValue: config.global.thresholds)
        _pacing = State(initialValue: config.global.pacing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    presetSection
                    connectionCard
                    // Everything below is a grouped card of collapsible rows, so
                    // Settings stays short; click a row to expand just that one.
                    VStack(spacing: 0) {
                        disclosureRow("position", "HUD position", "macwindow")   { positionSection }
                        rowDivider
                        disclosureRow("theme", "Theme", "paintpalette")          { themeSection }
                        rowDivider
                        disclosureRow("behaviour", "Behaviour", "slider.horizontal.3") { behaviourSection }
                        rowDivider
                        disclosureRow("levels", "Alert levels", "bell.badge")    { thresholdsSection }
                        rowDivider
                        disclosureRow("left", "Left pill", "l.square")           {
                            slotSection(caption: "The icon just left of the notch.", editor: $left, kind: .left)
                        }
                        rowDivider
                        disclosureRow("right", "Right pill", "r.square")         {
                            slotSection(caption: "The icon just right of the notch.", editor: $right, kind: .right)
                        }
                        rowDivider
                        disclosureRow("panel", "Panel", "list.bullet.rectangle") { panelSection }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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

    /// One collapsible section as a styled grouped-list row (icon · title ·
    /// chevron, hover highlight) that reveals its content when expanded. One
    /// generic row drives every section; adding another is a single
    /// `disclosureRow(id, title, icon) { … }` call plus a `rowDivider`.
    private func disclosureRow<Content: View>(_ id: String, _ title: String, _ icon: String,
                                              @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureRow(icon: icon, title: title, isOpen: sectionBinding(id), content: content)
    }

    /// The hairline between rows in the grouped card, inset under the title.
    private var rowDivider: some View {
        Divider().overlay(Color.primary.opacity(0.06)).padding(.leading, 44)
    }

    /// Two-way binding into the `expanded` set for one section id.
    private func sectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { open in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if open { expanded.insert(id) } else { expanded.remove(id) }
                    }
                })
    }

    /// One grouped-list row: an SF Symbol, the title, and a chevron that rotates
    /// when open, with a hover highlight; its content drops in below when open.
    /// Owns its own hover state so the wrapper stays a plain generic component.
    private struct DisclosureRow<Content: View>: View {
        let icon: String
        let title: String
        @Binding var isOpen: Bool
        let content: () -> Content
        @State private var hover = false

        var body: some View {
            VStack(spacing: 0) {
                Button { isOpen.toggle() } label: {
                    HStack(spacing: 11) {
                        Image(systemName: icon)
                            .font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 22)
                        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12).frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(hover ? Color.primary.opacity(0.05) : Color.clear)
                .onHover { hover = $0 }

                if isOpen {
                    VStack(alignment: .leading, spacing: 8) { content() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 14)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Perch Settings").font(.system(size: 16, weight: .semibold))
                Text("Pick what each spot shows. Editing preset: \(activePreset)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                updateButton
                // The running version, so it's always clear what you're on.
                Text("Version \(PerchVersion.current)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    /// Top-right update control. Reads the shared update state so it reflects the
    /// live flow — "Check for Updates" → "Update to 1.2.1" → "Downloading…" →
    /// "Up to date" — and installs in place when one is found. "Up to date" stays
    /// clickable so the user can re-check on demand.
    private var updateButton: some View {
        let status = updateModel.updateStatus
        return Button(action: onCheckUpdate) {
            HStack(spacing: 6) {
                Image(systemName: status.symbolName)
                Text(status.buttonTitle)
            }
            .font(.system(size: 12, weight: status.isHighlighted ? .semibold : .medium))
        }
        .buttonStyle(.borderedProminent)
        .tint(status.isHighlighted ? .accentColor : Color.secondary.opacity(0.25))
        .foregroundStyle(status.isHighlighted ? Color.white : Color.primary)
        .controlSize(.large)
        .disabled(!status.isActionable)
        .help(status == .upToDate ? "Up to date — click to check again"
                                  : "Check for and install Perch updates")
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

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A compact grid of preview tiles — each theme shown on its own
            // surface, the selected one ringed. Far tighter than a full-width row
            // per theme, and the swatch IS the choice. Applies on Save.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(Theme.allCases) { t in
                    themeTile(t)
                }
            }
            Text("Colours the pills and panel. “System” is the original look.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// One selectable theme tile: a mini preview on the theme's own surface
    /// (status dots + a name in the theme's own ink), ringed when selected.
    private func themeTile(_ t: Theme) -> some View {
        let selected = theme == t.id
        let p = t.palette
        return Button {
            theme = t.id
        } label: {
            HStack(spacing: 8) {
                Text(t.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(p.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    ForEach(Array([p.good, p.warning, p.critical, p.accent].enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 9, height: 9)
                    }
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(p.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(p.surface))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : p.onSurface.opacity(0.15),
                              lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open the panel automatically when something goes red",
                   isOn: $autoOpenOnRed)
                .toggleStyle(.checkbox).font(.system(size: 12))
            Toggle("Show alerts as a banner in the notch",
                   isOn: $notchBanner)
                .toggleStyle(.checkbox).font(.system(size: 12))
            HStack(spacing: 8) {
                Text("Quiet hours").font(.system(size: 12)).frame(width: 90, alignment: .leading)
                TextField("22:00-08:00", text: $quietHours)
                    .textFieldStyle(.roundedBorder).frame(width: 130)
                Text("no notifications in this window").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Alert levels (user-tunable thresholds)

    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When each metric turns amber (warn) and red (critical). Red is what pops the panel.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("WARN").font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(Color.orange)
                    Text("CRITICAL").font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(Color.red)
                }
                thresholdIntRow("CPU", "%", $thresholds.cpuWarn, $thresholds.cpuCritical, 10...100, 5)
                thresholdIntRow("Memory", "%", $thresholds.memoryWarn, $thresholds.memoryCritical, 10...100, 5)
                thresholdIntRow("Disk used", "%", $thresholds.diskWarn, $thresholds.diskCritical, 10...100, 5)
                thresholdDoubleRow("Swap", "GB", $thresholds.swapWarnGB, $thresholds.swapCriticalGB, 0.5...64, 0.5)
                thresholdDoubleRow("Load / core", "×", $thresholds.loadWarnRatio, $thresholds.loadCriticalRatio, 0.2...4, 0.1)
            }

            HStack(spacing: 10) {
                Button("Reset to defaults") { thresholds = .standard }
                    .controlSize(.small).font(.system(size: 11))
                Text("Thermal is macOS's own throttle-pressure signal — not a level you set.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 4)
            Text("Alert pacing").font(.system(size: 12, weight: .semibold))
            Text("Stops a metric flapping at its limit from alerting every few seconds.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Wait before alerting").font(.system(size: 12))
                    pacingCell($pacing.dwellSeconds, 0...60, 5, "\(pacing.dwellSeconds)s")
                }
                GridRow {
                    Text("Don't repeat for").font(.system(size: 12))
                    pacingCell($pacing.cooldownSeconds, 0...600, 30,
                               pacing.cooldownSeconds >= 60 ? "\(pacing.cooldownSeconds / 60)m" : "\(pacing.cooldownSeconds)s")
                }
            }
        }
    }

    /// One metric's row: name, then compact warn + critical stepper cells whose
    /// value text is fixed-width so the three columns line up in the grid.
    @ViewBuilder
    private func thresholdIntRow(_ name: String, _ unit: String, _ warn: Binding<Int>,
                                 _ crit: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int) -> some View {
        GridRow {
            Text(name).font(.system(size: 12))
            stepperCell("\(warn.wrappedValue)\(unit)", .orange) { Stepper("", value: warn, in: range, step: step).labelsHidden() }
            stepperCell("\(crit.wrappedValue)\(unit)", .red) { Stepper("", value: crit, in: range, step: step).labelsHidden() }
        }
    }

    @ViewBuilder
    private func thresholdDoubleRow(_ name: String, _ unit: String, _ warn: Binding<Double>,
                                    _ crit: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double) -> some View {
        GridRow {
            Text(name).font(.system(size: 12))
            stepperCell(String(format: "%.1f%@", warn.wrappedValue, unit), .orange) { Stepper("", value: warn, in: range, step: step).labelsHidden() }
            stepperCell(String(format: "%.1f%@", crit.wrappedValue, unit), .red) { Stepper("", value: crit, in: range, step: step).labelsHidden() }
        }
    }

    /// A value label (fixed width, right-aligned, tabular) next to a bare stepper.
    /// The width fits the widest value shown (e.g. "64.0GB"). Used by both the
    /// threshold cells and the pacing cells — one widget, not two.
    private func stepperCell(_ text: String, _ tint: Color, @ViewBuilder _ stepper: () -> some View) -> some View {
        HStack(spacing: 5) {
            Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(tint).frame(width: 52, alignment: .trailing)
            stepper()
        }
    }

    private func pacingCell(_ value: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int, _ text: String) -> some View {
        stepperCell(text, Color.secondary) { Stepper("", value: value, in: range, step: step).labelsHidden() }
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

    private func slotSection(caption: String, editor: Binding<SlotEditor>, kind: SlotKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            modulePicker(editor: editor, kind: kind)
            settingsFields(for: editor)
        }
    }

    /// Which slot a picker is for (kept for call-site clarity; every module is
    /// selectable in every slot now — you can watch the same module type in more
    /// than one place, e.g. Pull requests for two different repos).
    private enum SlotKind: Equatable { case left, right, panel(Int) }

    /// A module picker whose choices are grouped by what they need, so the
    /// local-vs-GitHub distinction is obvious *before* you pick. Every module is
    /// offered in every slot — duplicates of a configurable module (a second
    /// repo, another URL, another port) are exactly what makes the HUD yours.
    private func modulePicker(editor: Binding<SlotEditor>, kind: SlotKind) -> some View {
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
                            Button(entry.pickerLabel) {
                                editor.wrappedValue.moduleID = entry.id
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
                Text("The list shown when you click the notch.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
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
    /// whatever that pill held. If the OTHER pill already holds this exact same
    /// binding (module + settings), that pill is cleared so an identical thing
    /// isn't pinned to both pills. A same-type-but-different-config pill is fine.
    private func promote(_ index: Int, toLeft: Bool) {
        guard panel.indices.contains(index) else { return }
        let item = panel[index]   // copy — the panel row stays put
        if toLeft {
            left = item
            if right.toBinding() == item.toBinding() { right = SlotEditor(binding: nil) }
        } else {
            right = item
            if left.toBinding() == item.toBinding() { left = SlotEditor(binding: nil) }
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
                                    quietHours: trimmed.isEmpty ? nil : trimmed,
                                    theme: theme, notchBanner: notchBanner,
                                    thresholds: thresholds, pacing: pacing)
        onSave(out)
    }

    // MARK: - Grouping

    /// Presentation for a picker group. The *classification* is the module's own
    /// declared `ModuleCategory` (in `ModuleSpecs`) — the view only supplies the
    /// section's label and icon, so a module is never mis-grouped by a heuristic.
    private enum ModuleGroup: CaseIterable {
        case local, github, web

        init(_ category: ModuleCategory) {
            switch category {
            case .local:  self = .local
            case .github: self = .github
            case .web:    self = .web
            }
        }

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
        ModuleGroup(entry.category)
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
