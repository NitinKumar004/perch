import Foundation
import PerchCore
import PerchModuleKit
import PerchSync

/// Watches a deploy/service health endpoint and shows healthy / degraded / down
/// on the notch. Configure the URL with the `url` setting and an optional
/// `label` (defaults to "deploy"). Uses hysteresis so a single blip doesn't
/// flap the pill: it flips to `down` only after two consecutive failures.
public struct DeployModule: NotchModule {
    public typealias State = HealthState

    public static let descriptor = ModuleDescriptor(
        id: "deploy.health",
        name: "Deploy health",
        summary: "Ping a health endpoint; healthy / degraded / down.",
        supportedSlots: [.leftPill, .rightPill, .panel],
        requiresConnection: false
    )

    private let probe: HealthProbe

    /// Production: probes the real network.
    public init() {
        self.probe = .live()
    }

    /// Test seam: inject a fake probe.
    init(probe: HealthProbe) {
        self.probe = probe
    }

    public func stream(_ context: ModuleContext) -> AsyncStream<Snapshot<HealthState>> {
        let clock = context.clock
        let probe = probe
        let urlString = context.settings["url"] ?? ""
        let interval = context.refreshSeconds(fallback: 20, minimum: 5)

        return AsyncStream { continuation in
            let store = VersionedStore<String, HealthState>(clock: clock)
            let key = urlString
            var consecutiveFailures = 0

            let task = Task {
                guard let url = URL(string: urlString), !urlString.isEmpty else {
                    continuation.yield(Snapshot(value: .unknown, freshness: .error("no url configured"), asOf: clock.now()))
                    return
                }
                continuation.yield(Snapshot(value: .unknown, freshness: .unknown, asOf: clock.now()))

                while !Task.isCancelled {
                    let observed = await probe.check(url)

                    // Hysteresis: require two failures in a row before showing down.
                    let state: HealthState
                    if observed == .down {
                        consecutiveFailures += 1
                        state = consecutiveFailures >= 2 ? .down : (await store.snapshot(forKey: key, ttl: .infinity)?.value ?? .unknown)
                    } else {
                        consecutiveFailures = 0
                        state = observed
                    }

                    let now = clock.now()
                    _ = await store.apply(state, forKey: key, version: now)
                    continuation.yield(Snapshot(value: state, freshness: .live, asOf: now))

                    try? await Task.sleep(for: .seconds(interval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func contextLabel(_ context: ModuleContext) -> String? {
        let urlString = context.settings["url"] ?? ""
        guard !urlString.isEmpty, let host = URL(string: urlString)?.host else { return "no URL set" }
        return host
    }

    public func face(for value: HealthState, in slot: Slot) -> PillFace {
        switch value {
        case .healthy:
            return PillFace(text: "up", symbolName: "checkmark.circle.fill", tint: .good, tooltip: "Healthy")
        case .degraded:
            return PillFace(text: "deg", symbolName: "exclamationmark.triangle.fill", tint: .warning, tooltip: "Degraded")
        case .down:
            return PillFace(text: "down", symbolName: "xmark.octagon.fill", tint: .critical, tooltip: "Unreachable")
        case .unknown:
            return PillFace(text: "…", symbolName: "questionmark.circle", tint: .neutral, tooltip: "Checking")
        }
    }
}
