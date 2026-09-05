import Foundation
import PerchCore

/// Type-erased wrapper so a registry can hold heterogeneous modules in one
/// array. It also collapses the module's `stream` + `face` into a single stream
/// of ready-to-render `PillContent`, so the shell never sees a module's `State`
/// — the erasure is where the SDK boundary is enforced.
public struct AnyNotchModule: Sendable {
    public let descriptor: ModuleDescriptor
    private let makeStream: @Sendable (ModuleContext, Slot) -> AsyncStream<PillContent>

    public init<M: NotchModule>(_ module: M) {
        self.descriptor = M.descriptor
        self.makeStream = { context, slot in
            AsyncStream<PillContent> { continuation in
                let task = Task {
                    for await snapshot in module.stream(context) {
                        let face = module.face(for: snapshot.value, in: slot)
                        continuation.yield(
                            PillContent(face: face, freshness: snapshot.freshness, asOf: snapshot.asOf)
                        )
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    /// A stream of rendered pill content for the given slot. Cancelling the
    /// consuming task tears down the module's underlying work.
    public func pillStream(_ context: ModuleContext, slot: Slot) -> AsyncStream<PillContent> {
        makeStream(context, slot)
    }
}
