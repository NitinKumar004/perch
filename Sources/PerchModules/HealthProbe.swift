import Foundation

/// The classified result of probing one endpoint.
public enum HealthState: Sendable, Equatable {
    case healthy       // 2xx
    case degraded      // reachable but a non-2xx status
    case down          // could not reach it at all
    case unknown       // not yet probed
}

/// Probes an HTTP endpoint and classifies its health. Abstracted behind a
/// closure transport so tests can drive it without real network I/O.
struct HealthProbe: Sendable {
    /// Returns the HTTP status code for a URL, or `nil` if it was unreachable
    /// (DNS/TLS/timeout). Injectable for tests.
    let statusFor: @Sendable (URL) async -> Int?

    /// The real probe: a short-timeout GET via URLSession.
    static func live(timeout: TimeInterval = 5) -> HealthProbe {
        HealthProbe { url in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode
            } catch {
                return nil
            }
        }
    }

    func check(_ url: URL) async -> HealthState {
        guard let status = await statusFor(url) else { return .down }
        return (200..<300).contains(status) ? .healthy : .degraded
    }
}
