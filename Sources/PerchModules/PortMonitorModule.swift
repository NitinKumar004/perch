import Foundation
import PerchCore
import PerchModuleKit

/// Whether a watched local port is currently accepting connections.
public struct PortStatus: Sendable, Equatable {
    public var port: UInt16
    public var isUp: Bool
    public var label: String
    public static let unknown = PortStatus(port: 0, isUp: false, label: "")
    public init(port: UInt16, isUp: Bool, label: String) {
        self.port = port
        self.isUp = isUp
        self.label = label
    }
}

/// A fully local, zero-setup module: is your dev server up? Pings a local TCP
/// port on a light interval and shows up / down — so you know your `:3000` (or
/// any port) is listening without switching to the terminal. Configure `port`
/// and an optional `label`.
public struct PortMonitorModule: NotchModule {
    public typealias State = PortStatus

    public static let descriptor = ModuleDescriptor(
        id: "system.port",
        name: "Dev server",
        summary: "Is a local port listening? (e.g. your dev server on :3000)",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<PortStatus>> {
        let port = UInt16(context.int("port", fallback: 3000, minimum: 1, maximum: 65535))
        let label = context.settings["label"] ?? ":\(port)"
        return .periodic(every: context.refreshSeconds(fallback: 5, minimum: 2),
                         clock: context.clock,
                         seed: PortStatus(port: port, isUp: false, label: label)) {
            // The sample closure already runs off the main actor on the polling
            // task, so probe inline — a detached task wouldn't inherit
            // cancellation and would outlive a teardown mid-probe.
            PortStatus(port: port, isUp: PortProbe.isOpen(port: port), label: label)
        }
    }

    public func face(for value: PortStatus, in slot: Slot) -> PillFace {
        // Up is green; down is neutral (a stopped dev server is normal, not an
        // error) so it never triggers auto-open-on-red.
        value.isUp
            ? PillFace(text: value.label, symbolName: "bolt.horizontal.circle.fill", tint: .good,
                       tooltip: "\(value.label) is up")
            : PillFace(text: value.label, symbolName: "bolt.horizontal.circle", tint: .neutral,
                       tooltip: "\(value.label) is down")
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let port = context.int("port", fallback: 3000, minimum: 1, maximum: 65535)
        return "localhost:\(port)"
    }

    public func detail(for value: PortStatus) -> [DetailRow] {
        [DetailRow(id: "port-\(value.port)",
                   title: value.label,
                   subtitle: value.isUp ? "listening on 127.0.0.1:\(value.port)" : "not listening",
                   tint: value.isUp ? .good : .neutral,
                   symbolName: value.isUp ? "checkmark.circle.fill" : "circle.dashed")]
    }
}
