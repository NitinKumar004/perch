import Foundation
import PerchCore
import PerchModuleKit
import PerchSync

/// A demo CI module that routes a fake provider's events through the real
/// `VersionedStore`, so the skeleton exercises the full accuracy path:
/// provider → engine (ordering + freshness) → snapshot → pill.
///
/// When the real `GitHubBuildsModule` arrives it implements this exact same
/// protocol; nothing else in the app changes.
public struct FakeBuildModule: NotchModule {
    public typealias State = BuildState

    public static let descriptor = ModuleDescriptor(
        id: "demo.build",
        name: "Build (demo)",
        summary: "A simulated CI signal to prove the pipeline end to end.",
        supportedSlots: [.leftPill, .panel],
        requiresConnection: false
    )

    public init() {}

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<BuildState>> {
        let clock = context.clock
        return AsyncStream { continuation in
            let store = VersionedStore<String, BuildState>(clock: clock)
            let key = "main"
            let provider = FakeBuildProvider()

            let task = Task {
                // Honest initial state: we haven't confirmed anything yet.
                continuation.yield(Snapshot(value: .unknown, freshness: .unknown, asOf: clock.now()))

                for await event in provider.events() {
                    let accepted = await store.apply(event.state, forKey: key, version: event.version)
                    // Only emit when the engine accepted a newer value. A rejected
                    // (stale/out-of-order) event correctly changes nothing.
                    if accepted, let snapshot = await store.snapshot(forKey: key, ttl: 3600) {
                        continuation.yield(snapshot)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func face(for value: BuildState, in slot: Slot) -> PillFace {
        switch value {
        case .unknown:
            return PillFace(text: "CI", symbolName: "questionmark.circle", tint: .neutral, tooltip: "No build data yet")
        case .running:
            return PillFace(text: "CI", symbolName: "arrow.triangle.2.circlepath", tint: .info, tooltip: "Build running")
        case .passing:
            return PillFace(text: "CI", symbolName: "checkmark.circle.fill", tint: .good, tooltip: "Build passing")
        case .failing:
            return PillFace(text: "CI", symbolName: "xmark.circle.fill", tint: .critical, tooltip: "Build failing")
        }
    }
}
