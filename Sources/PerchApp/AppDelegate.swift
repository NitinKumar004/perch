import AppKit
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
    private var statusItem: NSStatusItem?
    private var connectItem: NSMenuItem?
    private var isConnecting = false

    // GitHub auth is created once and shared by the API client.
    private let auth = GitHubAuth(
        flow: GitHubDeviceFlow(http: URLSessionHTTPClient()),
        store: KeychainTokenStore()
    )

    private let configStore = ConfigStore()
    private let settingsWindow = SettingsWindowController()
    private let notifier = Notifier()
    private let timerController = TimerController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        notifier.requestAuthorization()

        let actions = PanelActions(
            onConnect: { [weak self] in self?.startConnect() },
            onSettings: { [weak self] in self?.openSettings() },
            onReload: { [weak self] in self?.applyConfig() },
            onQuit: { NSApp.terminate(nil) },
            onAction: { [weak self] action in self?.handleAction(action) }
        )
        let controller = NotchWindowController(model: model, onActivate: { [weak self] in
            self?.handleActivate()
        }, panelActions: actions)
        controller.show()
        windowController = controller

        applyConfig()
        refreshConnectItem()
    }

    /// Read the user's layout.json and wire the notch from it. Called at launch
    /// and whenever the config changes, so customisation takes effect without a
    /// restart. Everything about which module sits where now comes from config.
    private func applyConfig() {
        binder?.cancelAll()
        model.leftPill = nil
        model.rightPill = nil
        model.panelItems = []   // reset so re-applying never duplicates rows

        let config = configStore.load()
        windowController?.setPosition(HUDPosition(rawValue: config.hudPosition) ?? .flank)
        guard let preset = config.current else { return }

        let factory = ModuleFactory(apiClient: GitHubAPIClient(auth: auth), timerController: timerController)
        let binder = SlotBinder(model: model, context: ModuleContext(), notifier: notifier)

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
                binder.seedPanelItem(id: "\(binding.module)#\(index)", module: module)
            }
        }
        for k in order {
            guard let group = groups[k], let module = factory.makeModule(for: group.binding) else { continue }
            binder.bindShared(module, settings: group.binding.settings,
                              pills: group.pills, panelIDs: group.panelIDs)
        }
        self.binder = binder
    }

    /// A pill was clicked: toggle the detail panel. The panel's own footer holds
    /// Connect / Settings / Reload / Quit, so everything is reachable from the
    /// notch without the menu-bar icon.
    private func handleActivate() {
        model.isPanelOpen.toggle()
        windowController?.setPanelOpen(model.isPanelOpen)
        if model.isPanelOpen { refreshConnectedFlag() }
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
        Task { [timerController] in
            switch verb {
            case "timer.toggle": await timerController.togglePause(id: id, now: Date())
            case "timer.reset":  await timerController.reset(id: id, now: Date())
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        menu.addItem(withTitle: "Quit Perch",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        statusItem = item
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
            onUseToken: { [weak self] pat in self?.signInWithToken(pat) }
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
            model.isConnected = true
            connectItem?.title = "GitHub: connected ✓"
            connectItem?.isEnabled = false
            applyConfig()
        }
    }

    private func refreshConnectItem() {
        Task {
            let connected = await auth.isConnected()
            model.isConnected = connected
            connectItem?.title = connected ? "GitHub: connected ✓" : "Connect GitHub…"
            connectItem?.isEnabled = !connected
        }
    }

    @objc private func connectGitHub() { startConnect() }

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

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                connectItem?.title = "Code \(code.userCode) copied — paste at github.com"

                // Print it loudly to the terminal too, so the code is always
                // readable even if the clipboard gets overwritten or the menu
                // title is hidden behind the notch.
                print("""

                ┌───────────────────────────────────────────────┐
                │  Perch · GitHub device login                  │
                │  Enter this code:  \(code.userCode)
                │  at: \(code.verificationUri)
                └───────────────────────────────────────────────┘

                """)

                if let url = URL(string: code.verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                try await auth.awaitAuthorization(code)
                model.isConnected = true
                connectItem?.title = "GitHub: connected ✓"
                connectItem?.isEnabled = false
            } catch {
                connectItem?.title = "GitHub: connect failed — retry"
            }
        }
    }
}
