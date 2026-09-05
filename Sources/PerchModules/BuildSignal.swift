import Foundation
import PerchCore
import PerchModuleKit

/// The state of a CI build, as a module would model it. Deliberately small and
/// `Sendable` so it can flow across the concurrency boundary.
public enum BuildState: Sendable, Equatable {
    case unknown
    case running
    case passing
    case failing
}

/// The shared "how a build looks as a pill" mapping, used by both the demo and
/// the real GitHub build module so a passing build always reads the same way.
func buildFace(for value: BuildState, in slot: Slot) -> PillFace {
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

/// One observation of a build's state from a source, stamped with the source's
/// own timestamp. The `version` is what the accuracy engine orders by — not the
/// moment we happened to receive it.
public struct BuildEvent: Sendable {
    public let state: BuildState
    public let version: Date

    public init(state: BuildState, version: Date) {
        self.state = state
        self.version = version
    }
}

/// Stands in for a real provider (GitHub Actions) during the skeleton phase.
/// It plays a scripted sequence — including one deliberately *out-of-order*
/// event — so the accuracy engine's ordering guarantee is visible in the live
/// path, not just in unit tests.
struct FakeBuildProvider: Sendable {
    func events() -> AsyncStream<BuildEvent> {
        AsyncStream { continuation in
            let task = Task {
                let base = Date()
                // (state, secondsFromBase, delayBeforeEmit)
                let script: [(BuildState, TimeInterval, Double)] = [
                    (.running, 0, 1),
                    (.passing, 4, 4),
                    (.running, 8, 4),
                    (.failing, 12, 4),
                    (.passing, 20, 4),
                ]
                for step in script {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(step.2))
                    continuation.yield(BuildEvent(state: step.0, version: base.addingTimeInterval(step.1)))

                    // Right after a failure, emit a STALE "passing" (an older
                    // version). The engine must reject it and keep showing red.
                    if step.0 == .failing {
                        continuation.yield(BuildEvent(state: .passing, version: base.addingTimeInterval(step.1 - 5)))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
