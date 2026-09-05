import AppKit
import PerchCore
import PerchModuleKit
import PerchModules
import PerchNotchUI

/// The composition root: the one place that knows about every layer. It builds
/// the module registry, applies the layout (which module goes in which slot),
/// shows the notch window, and starts the data loop.
///
/// In the next phase the hard-coded slot assignment below is replaced by a
/// validated `layout.json`; nothing else here changes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NotchViewModel()
    private var windowController: NotchWindowController?
    private var binder: SlotBinder?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        // Everything the app can show, registered by id.
        let registry = ModuleRegistry([
            AnyNotchModule(FakeBuildModule()),
            AnyNotchModule(ClockModule()),
        ])

        // Show the surface.
        let controller = NotchWindowController(model: model)
        controller.show()
        windowController = controller

        // Wire the layout: build → left pill, clock → right pill.
        let binder = SlotBinder(model: model, context: ModuleContext())
        if let build = registry.module(id: FakeBuildModule.descriptor.id) {
            binder.bind(build, to: .leftPill)
        }
        if let clock = registry.module(id: ClockModule.descriptor.id) {
            binder.bind(clock, to: .rightPill)
        }
        self.binder = binder
    }

    func applicationWillTerminate(_ notification: Notification) {
        binder?.cancelAll()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Perch")

        let menu = NSMenu()
        menu.addItem(withTitle: "Perch — notch HUD", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Perch",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
