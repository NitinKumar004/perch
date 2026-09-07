import AppKit
import SwiftUI
import PerchCore
import PerchModuleKit
import PerchModules
import PerchNotchUI
import PerchGitHub
import PerchConfig

/// The composition root: the one place that knows about every layer. It builds
/// auth, the module registry, applies the layout (which module goes in which
/// slot), shows the notch window, and starts the data loop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NotchViewModel()
    private var windowController: NotchWindowController?
    private var binder: SlotBinder?
    /// Panel-item id → the config binding it came from, for drag-to-reorder.
    /// Only explicitly-placed panel modules are recorded (auto-surfaced pill rows
    /// aren't reorderable). Rebuilt every applyConfig.
    private var panelBindings: [String: SlotBinding] = [:]
    private var statusItem: NSStatusItem?
    private var connectItem: NSMenuItem?
    private var disconnectItem: NSMenuItem?
    private var isConnecting = false

    // GitHub auth is created once and shared by the API client.
    private let auth = GitHubAuth(
        flow: GitHubDeviceFlow(http: URLSessionHTTPClient()),
        store: KeychainTokenStore()
    )

    private let configStore = ConfigStore()
    private let settingsWindow = SettingsWindowController()
    private let welcomeWindow = WelcomeWindowController()
    private let deviceCodeWindow = DeviceCodeWindowController()
    private let notifier = Notifier()
    private let timerController = TimerController()
    private let clipboardController = ClipboardController()
    private let fileShelfController = FileShelfController()
    private let updateChecker = UpdateChecker()
    private var configWatcher: ConfigWatcher?
    private var updateItem: NSMenuItem?
    private var pendingUpdate: UpdateInfo?
    private var updateTimer: Timer?
    /// In-flight guards so a double-click or a timer firing during a manual check
    /// can't start two concurrent downloads/installs racing on the same bundle.
    private var isCheckingForUpdate = false
    private var isInstallingUpdate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isFirstRun = !FileManager.default.fileExists(atPath: ConfigStore.defaultFileURL.path)
        installStatusItem()
        notifier.requestAuthorization()

        let actions = PanelActions(
            onConnect: { [weak self] in self?.startConnect() },
            onSettings: { [weak self] in self?.openSettings() },
            onReload: { [weak self] in self?.applyConfig() },
            onQuit: { [weak self] in self?.confirmQuit() },
            onAction: { [weak self] action in self?.handleAction(action) },
            onDropFiles: { [weak self] urls in self?.handleDroppedFiles(urls) ?? false },
            onReorder: { [weak self] orderedIDs in self?.reorderPanel(orderedIDs: orderedIDs) }
        )
        let controller = NotchWindowController(model: model, onActivate: { [weak self] in
            self?.handleActivate()
        }, panelActions: actions)
        controller.show()
        windowController = controller

        applyConfig()
        refreshConnectItem()

        // Hot-reload: re-wire the notch whenever layout.json changes on disk.
        let watcher = ConfigWatcher(fileURL: ConfigStore.defaultFileURL) { [weak self] in
            self?.applyConfig()
        }
        watcher.start()
        configWatcher = watcher

        // First launch: greet the user, and default to launch-at-login so a
        // background agent with no Dock icon comes back on its own after a
        // reboot. The Settings toggle still lets them turn it off — we only set
        // this default once, on the very first run.
        if isFirstRun {
            LoginItem.setEnabled(true)
            showWelcome()
        }

        // Check for a newer release now, then every 6 hours — so a long-running
        // Mac gets the "Update available" prompt the same day without a restart.
        checkForUpdates(userInitiated: false)
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates(userInitiated: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    /// Ask GitHub Releases whether a newer Perch exists. On success it updates
    /// the menu item and (once) notifies; `userInitiated` also opens the page.
    private func checkForUpdates(userInitiated: Bool) {
        guard !isCheckingForUpdate, !isInstallingUpdate else { return }
        isCheckingForUpdate = true
        Task { [updateChecker, notifier] in
            defer { self.isCheckingForUpdate = false }
            guard let info = await updateChecker.check() else {
                if userInitiated {
                    self.updateItem?.title = "Perch is up to date"
                    self.model.updateStatus = .upToDate
                }
                return
            }
            self.pendingUpdate = info
            self.updateItem?.title = "Update to \(info.version) — install now"
            self.model.updateStatus = .available(version: info.version)
            if userInitiated {
                self.installUpdate(info)
            } else {
                notifier.post(ModuleAlert(
                    id: "perch-update-\(info.version)",
                    title: "Perch \(info.version) is available",
                    body: "Open Perch’s panel → “Update to \(info.version)” to install.",
                    url: info.pageURL))
            }
        }
    }

    @objc private func checkForUpdatesClicked() {
        // If we already found one, clicking installs it; otherwise run a fresh
        // check and install if found.
        if let info = pendingUpdate {
            installUpdate(info)
        } else {
            updateItem?.title = "Checking…"
            model.updateStatus = .checking
            checkForUpdates(userInitiated: true)
        }
    }

    /// Install a found update in place, then quit + relaunch. Falls back to
    /// opening the release page if the app isn't bundle-installed (swift run) or
    /// the swap fails.
    private func installUpdate(_ info: UpdateInfo) {
        guard let zip = URL(string: info.zipURL) else { return }
        guard !isInstallingUpdate else { return }   // one install at a time
        isInstallingUpdate = true
        updateItem?.title = "Downloading \(info.version)…"
        model.updateStatus = .downloading(version: info.version)
        Task {
            let result = await SelfUpdater.installUpdate(from: zip)
            switch result {
            case .relaunching:
                break   // app is terminating; the swap script relaunches it
            case .unsupported, .failed:
                self.isInstallingUpdate = false   // stayed alive; allow a retry
                self.updateItem?.title = "Open \(info.version) release page"
                self.model.updateStatus = .releasePage(version: info.version)
                if let page = URL(string: info.pageURL) { NSWorkspace.shared.open(page) }
            }
        }
    }

    /// Read the user's layout.json and wire the notch from it. Called at launch
    /// and whenever the config changes, so customisation takes effect without a
    /// restart. Everything about which module sits where now comes from config.
    private func applyConfig() {
        binder?.cancelAll()
        model.leftPill = nil
        model.rightPill = nil
        model.panelItems = []   // reset so re-applying never duplicates rows
        panelBindings = [:]     // rebuilt below as explicit panel rows are seeded

        let config = configStore.load()
        notifier.configure(config.global)
        configWatcher?.markApplied()   // our own read isn't an "external" change
        model.palette = (Theme(rawValue: config.global.theme) ?? .system).palette
        windowController?.setPosition(HUDPosition(rawValue: config.hudPosition) ?? .flank)
        guard let preset = config.current else { return }

        let autoOpenOnRed = config.global.autoOpenOnRed
        let factory = ModuleFactory(apiClient: GitHubAPIClient(auth: auth),
                                    timerController: timerController,
                                    clipboardController: clipboardController,
                                    fileShelfController: fileShelfController)
        let binder = SlotBinder(model: model, context: ModuleContext(), notifier: notifier,
                                onCritical: { [weak self] in
                                    guard autoOpenOnRed else { return }
                                    self?.autoOpenPanel()
                                },
                                onStatusChange: { [weak self] in self?.refreshStatusIcon() })

        // Group every placement (pills + panel rows) by (module id + settings)
        // so identical configs share one poll instead of each fetching.
        struct Group { let binding: SlotBinding; var pills: Set<Slot> = []; var panelIDs: [String] = [] }
        var groups: [String: Group] = [:]
        var order: [String] = []

        func key(_ b: SlotBinding) -> String {
            b.module + "|" + b.settings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        }
        func ensure(_ b: SlotBinding) -> String {
            let k = key(b)
            if groups[k] == nil { groups[k] = Group(binding: b); order.append(k) }
            return k
        }

        if let left = preset.leftPill { groups[ensure(left)]?.pills.insert(.leftPill) }
        if let right = preset.rightPill { groups[ensure(right)]?.pills.insert(.rightPill) }
        for (index, binding) in preset.panel.enumerated() {
            let k = ensure(binding)
            let id = "\(binding.module)#\(index)"
            groups[k]?.panelIDs.append(id)
        }

        // Seed panel rows in config order, then start one shared poll per group.
        for (index, binding) in preset.panel.enumerated() {
            if let module = factory.makeModule(for: binding) {
                let id = "\(binding.module)#\(index)"
                binder.seedPanelItem(id: id, module: module)
                panelBindings[id] = binding   // this row is reorderable
            }
        }
        for (groupIndex, k) in order.enumerated() {
            guard var group = groups[k], let module = factory.makeModule(for: group.binding) else { continue }
            // A "detail-first" module (clipboard, file shelf, PR queue) placed
            // only in a pill would be a dead end — the pill shows just a count.
            // Also surface it in the panel so its contents stay reachable. The id
            // includes the group index so two same-type pills (e.g. PRs for two
            // different repos) don't collide on one auto-seed id.
            if module.descriptor.detailFirst, !group.pills.isEmpty, group.panelIDs.isEmpty {
                let autoID = "\(group.binding.module)#pill-\(groupIndex)"
                binder.seedPanelItem(id: autoID, module: module)
                group.panelIDs.append(autoID)
            }
            binder.bindShared(module, settings: group.binding.settings,
                              pills: group.pills, panelIDs: group.panelIDs)
        }
        self.binder = binder
    }

    /// Apply a drag reorder: sync the live rows to the order the panel settled
    /// on, then persist it to the active preset — without a full reload, so polls
    /// keep running and nothing flashes.
    private func reorderPanel(orderedIDs: [String]) {
        let currentOrder = model.panelItems.map(\.id)
        guard orderedIDs != currentOrder else { return }

        let byID = Dictionary(model.panelItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var items = orderedIDs.compactMap { byID[$0] }
        // Keep any rows the panel didn't mention (shouldn't happen) so a reorder
        // can never drop a live row.
        let mentioned = Set(orderedIDs)
        items.append(contentsOf: model.panelItems.filter { !mentioned.contains($0.id) })
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            model.panelItems = items
        }

        // Persist the explicit rows in their new order. Bail if any lost its
        // binding, so a reorder can never silently drop a module from the config.
        let newPanel = items.compactMap { panelBindings[$0.id] }
        var config = configStore.load()
        let key = config.presets[config.activePreset] != nil
            ? config.activePreset : (config.presets.keys.sorted().first ?? "default")
        guard let preset = config.presets[key], newPanel.count == preset.panel.count else { return }
        config.presets[key]?.panel = newPanel
        try? configStore.save(config)
        configWatcher?.markApplied()   // our own write — don't bounce back as a reload
    }

    /// A pill was clicked: toggle the detail panel. The panel's own footer holds
    /// Connect / Settings / Reload / Quit, so everything is reachable from the
    /// notch without the menu-bar icon.
    private func handleActivate() {
        model.isPanelOpen.toggle()
        windowController?.setPanelOpen(model.isPanelOpen)
        if model.isPanelOpen { refreshConnectedFlag() }
    }

    /// Tint the menu-bar bird to the worst current state — red if anything is
    /// failing, amber if anything is warning — so a failure is visible even in
    /// fullscreen or on a Mac with no notch. Neutral (default) when all is well.
    private func refreshStatusIcon() {
        var tints: [Tint] = []
        if let l = model.leftPill { tints.append(l.face.tint) }
        if let r = model.rightPill { tints.append(r.face.tint) }
        tints.append(contentsOf: model.panelItems.map { $0.content.face.tint })
        let color: NSColor? = tints.contains(.critical) ? .systemRed
            : (tints.contains(.warning) ? .systemYellow : nil)
        statusItem?.button?.contentTintColor = color
    }

    /// Pop the panel because something went red (auto-open-on-red). No-op if it's
    /// already open, so a flapping build doesn't yank focus repeatedly.
    private func autoOpenPanel() {
        guard !model.isPanelOpen else { return }
        model.isPanelOpen = true
        windowController?.setPanelOpen(true)
        refreshConnectedFlag()
    }

    /// Keep the model's connected flag current so the panel shows Connect only
    /// when needed.
    private func refreshConnectedFlag() {
        Task { model.isConnected = await auth.isConnected() }
    }

    /// Route a module's detail-row action. Today: focus-timer pause/reset,
    /// encoded as "timer.toggle:<id>" / "timer.reset:<id>".
    private func handleAction(_ action: String) {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let (verb, id) = (parts[0], parts[1])
        Task { [timerController, clipboardController, fileShelfController] in
            switch verb {
            case "timer.toggle": await timerController.togglePause(id: id, now: Date())
            case "timer.reset":  await timerController.reset(id: id, now: Date())
            case "clip.copy":
                // `id` is the exact entry text — copy it straight back, no index
                // lookup, so a reshuffled list can't select the wrong entry.
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                }
            case "clip.clear":
                await clipboardController.clear()
            case "shelf.open":
                // `id` is the file path — reveal it directly in Finder.
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: id)])
                }
            case "shelf.remove":
                // `id` is the file path — remove exactly that file.
                await fileShelfController.remove(path: id)
            default: break
            }
        }
    }

    /// Record files dropped onto the panel into the file shelf. Returns true so
    /// the panel confirms the drop even though recording is async.
    private func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        Task { [fileShelfController] in
            for url in urls { await fileShelfController.add(path: url.path) }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        configWatcher?.stop()
        updateTimer?.invalidate()
        binder?.cancelAll()
    }

    // MARK: - Menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Perch")

        let menu = NSMenu()
        menu.addItem(withTitle: "Perch — notch HUD", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let connect = NSMenuItem(title: "Connect GitHub…", action: #selector(connectGitHub), keyEquivalent: "")
        connect.target = self
        menu.addItem(connect)
        connectItem = connect

        let disconnect = NSMenuItem(title: "Disconnect GitHub", action: #selector(disconnectClicked), keyEquivalent: "")
        disconnect.target = self
        disconnect.isEnabled = false   // enabled only once connected
        menu.addItem(disconnect)
        disconnectItem = disconnect

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let edit = NSMenuItem(title: "Edit Configuration File…", action: #selector(editConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        let reload = NSMenuItem(title: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        updateItem = update

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Perch", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func quitClicked() { confirmQuit() }

    /// Confirm before quitting — a background agent has no Dock icon, so without
    /// this a user who quits can't tell how to get Perch back. The dialog spells
    /// out that reopening is a Spotlight search away.
    private func confirmQuit() {
        // The detail panel floats at status-bar window level, so it would draw on
        // top of the modal alert and hide its title/message. Close it first so the
        // dialog is fully visible.
        if model.isPanelOpen {
            model.isPanelOpen = false
            windowController?.setPanelOpen(false)
        }
        let alert = NSAlert()
        alert.messageText = "Quit Perch?"
        alert.informativeText = "Perch will stop watching your builds and your Mac.\n\nTo reopen it later: press ⌘-Space, type “Perch”, and hit Return."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)   // bring the dialog forward for an accessory app
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    /// Open layout.json in the user's editor. Loading first guarantees the file
    /// exists (defaults are written on first run), so there is always something
    /// to edit.
    @objc private func editConfig() {
        _ = configStore.load()
        NSWorkspace.shared.open(ConfigStore.defaultFileURL)
    }

    /// Re-read the config and re-wire the notch — no restart needed.
    @objc private func reloadConfig() {
        applyConfig()
    }

    /// First-launch greeting, shown once when there's no config yet.
    private func showWelcome() {
        welcomeWindow.show(
            onConnect: { [weak self] in self?.startConnect() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
    }

    /// Open the native settings window; saving persists the config and re-wires
    /// the notch immediately.
    @objc private func openSettings() {
        // Close the notch drop-down first so it doesn't float over the window.
        model.isPanelOpen = false
        windowController?.setPanelOpen(false)

        let config = configStore.load()
        settingsWindow.show(
            config: config,
            isConnected: { [auth] in await auth.isConnected() },
            onConnect: { [weak self] in self?.startConnect() },
            onUseToken: { [weak self] pat in self?.signInWithToken(pat) },
            onUseCLI: { [weak self] in self?.signInWithGitHubCLI() },
            onDisconnect: { [weak self] in self?.disconnect() },
            updateModel: model,
            onCheckUpdate: { [weak self] in self?.checkForUpdatesClicked() }
        ) { [weak self] edited in
            guard let self else { return }
            try? self.configStore.save(edited)
            self.applyConfig()
        }
    }

    /// Save a pasted Personal Access Token as the GitHub credential, then re-wire
    /// so modules pick it up immediately (it can read private repos the app can't).
    private func signInWithToken(_ pat: String) {
        guard !pat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            try? await auth.signIn(withPersonalAccessToken: pat)
            markConnected()
            applyConfig()
        }
    }

    /// Sign in by borrowing the GitHub CLI's token — one click, sees everything
    /// the user's `gh` login can. Reports back if `gh` is missing or logged out.
    private func signInWithGitHubCLI() {
        Task {
            let outcome = await Task.detached { GitHubCLI.fetchToken() }.value
            switch outcome {
            case .token(let token):
                try? await auth.signIn(withPersonalAccessToken: token)
                markConnected()
                applyConfig()
            case .notInstalled:
                connectItem?.title = "GitHub CLI (gh) not found"
            case .notLoggedIn:
                connectItem?.title = "Run `gh auth login` first"
            }
        }
    }

    private func markConnected() {
        model.isConnected = true
        connectItem?.title = "GitHub: connected ✓"
        connectItem?.isEnabled = false
        disconnectItem?.isEnabled = true
    }

    private func refreshConnectItem() {
        Task {
            let connected = await auth.isConnected()
            model.isConnected = connected
            connectItem?.title = connected ? "GitHub: connected ✓" : "Connect GitHub…"
            connectItem?.isEnabled = !connected
            disconnectItem?.isEnabled = connected
        }
    }

    @objc private func connectGitHub() { startConnect() }

    @objc private func disconnectClicked() { disconnect() }

    /// Forget the GitHub credential — cleared from the Keychain and memory — then
    /// re-wire so GitHub modules fall back to their signed-out state. The user can
    /// reconnect at any time.
    private func disconnect() {
        Task {
            try? await auth.signOut()
            model.isConnected = false
            connectItem?.title = "Connect GitHub…"
            connectItem?.isEnabled = true
            disconnectItem?.isEnabled = false
            applyConfig()   // GitHub-backed modules refresh into their disconnected state
        }
    }

    /// Runs the device-flow login: shows the user their code, opens github.com,
    /// and waits for them to authorize — then the build pill starts working on
    /// its next poll (no restart needed). Reachable from both the menu item and
    /// a click on the notch pill. Guarded so repeated clicks don't stack logins.
    private func startConnect() {
        guard !isConnecting else { return }
        isConnecting = true

        Task {
            defer { isConnecting = false }

            if await auth.isConnected() {
                connectItem?.title = "GitHub: connected ✓"
                connectItem?.isEnabled = false
                return
            }
            do {
                let code = try await auth.beginDeviceLogin()

                // Surface the code clearly: a window shows it big + copies it +
                // opens the GitHub page, so the user always knows what to enter.
                deviceCodeWindow.show(code: code.userCode, verificationUri: code.verificationUri)
                connectItem?.title = "Enter code \(code.userCode) — see the window"
                if let url = URL(string: code.verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                try await auth.awaitAuthorization(code)
                markConnected()
                deviceCodeWindow.markConnected()
            } catch {
                connectItem?.title = "GitHub: connect failed — retry"
                deviceCodeWindow.markFailed()
            }
        }
    }
}
