import AppKit
import PerchCore
import PerchModuleKit
import PerchModules
import PerchNotchUI
import PerchGitHub

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

    // The repo the build pill watches. (Becomes user-configurable via layout.json.)
    private let watchedRepo = (owner: "NitinKumar004", name: "perch", branch: "main")

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        let client = GitHubAPIClient(auth: auth)
        let registry = ModuleRegistry([
            AnyNotchModule(GitHubBuildsModule(client: client,
                                              owner: watchedRepo.owner,
                                              repo: watchedRepo.name,
                                              branch: watchedRepo.branch)),
            AnyNotchModule(ClockModule()),
        ])

        let controller = NotchWindowController(model: model, onActivate: { [weak self] in
            self?.startConnect()
        })
        controller.show()
        windowController = controller

        // Layout: real build → left pill, clock → right pill.
        let binder = SlotBinder(model: model, context: ModuleContext())
        if let build = registry.module(id: GitHubBuildsModule.descriptor.id) {
            binder.bind(build, to: .leftPill)
        }
        if let clock = registry.module(id: ClockModule.descriptor.id) {
            binder.bind(clock, to: .rightPill)
        }
        self.binder = binder

        refreshConnectItem()
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
        menu.addItem(withTitle: "Quit Perch",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        statusItem = item
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
