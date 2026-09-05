import Foundation
import PerchCore

/// Type-erased wrapper so a registry can hold heterogeneous modules in one
/// array. It also collapses the module's `stream` + `face` into a single stream
/// of ready-to-render `PillContent`, so the shell never sees a module's `State`
/// — the erasure is where the SDK boundary is enforced.
public struct AnyNotchModule: Sendable {
    public let descriptor: ModuleDescriptor
    private let makeStream: @Sendable (ModuleContext, Slot) -> AsyncStream<ModuleRender>

    public init<M: NotchModule>(_ module: M) {
        self.descriptor = M.descriptor
        self.makeStream = { context, slot in
            AsyncStream<ModuleRender> { continuation in
                let task = Task {
                    var previous: M.State?
                    let contextLabel = module.contextLabel(context)
                    for await snapshot in module.stream(context) {
                        let face = module.face(for: snapshot.value, in: slot)
                        let pill = PillContent(face: face, freshness: snapshot.freshness, asOf: snapshot.asOf)
                        let detail = module.detail(for: snapshot.value)
                        let alert = module.notification(for: snapshot.value, previous: previous)
                        previous = snapshot.value
                        continuation.yield(ModuleRender(pill: pill, detail: detail, alert: alert, contextLabel: contextLabel))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    /// A stream of rendered pill + detail for the given slot. Cancelling the
    /// consuming task tears down the module's underlying work.
    public func renderStream(_ context: ModuleContext, slot: Slot) -> AsyncStream<ModuleRender> {
        makeStream(context, slot)
    }
}
