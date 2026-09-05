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

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        let controller = NotchWindowController(model: model, onActivate: { [weak self] in
            self?.handleActivate()
        })
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

        let config = configStore.load()
        guard let preset = config.current else { return }

        let factory = ModuleFactory(apiClient: GitHubAPIClient(auth: auth))
        let binder = SlotBinder(model: model, context: ModuleContext())

        if let left = preset.leftPill, let module = factory.makeModule(for: left) {
            binder.bind(module, to: .leftPill, settings: left.settings)
        }
        if let right = preset.rightPill, let module = factory.makeModule(for: right) {
            binder.bind(module, to: .rightPill, settings: right.settings)
        }
        for (index, binding) in preset.panel.enumerated() {
            if let module = factory.makeModule(for: binding) {
                binder.bindPanel(module, at: index, settings: binding.settings)
            }
        }
        self.binder = binder
    }

    /// A pill was clicked. If GitHub isn't connected yet, that's the priority —
    /// start the connect flow. Otherwise toggle the detail panel.
    private func handleActivate() {
        Task {
            if await !auth.isConnected() {
                startConnect()
            } else {
                model.isPanelOpen.toggle()
                windowController?.setPanelOpen(model.isPanelOpen)
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

        let edit = NSMenuItem(title: "Edit Configuration…", action: #selector(editConfig), keyEquivalent: ",")
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

    private func refreshConnectItem() {
        Task {
            let connected = await auth.isConnected()
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
                connectItem?.title = "GitHub: connected ✓"
                connectItem?.isEnabled = false
            } catch {
                connectItem?.title = "GitHub: connect failed — retry"
            }
        }
    }
}
