import Foundation

/// A count of pull requests in some queue, stamped with when we observed it.
public struct PRCountObservation: Sendable, Equatable {
    public let count: Int
    public let observedAt: Date

    public init(count: Int, observedAt: Date) {
        self.count = count
        self.observedAt = observedAt
    }
}

/// Which pull-request queue to count.
public enum PRQueue: String, Sendable {
    /// PRs where your review has been requested (waiting on you).
    case reviewRequested = "review-requested"
    /// PRs you opened.
    case authored = "author"
}

extension GitHubAPIClient {
    /// Count the authenticated user's open PRs in `queue`, optionally scoped to
    /// one `repo` ("owner/name"). Uses the search API, whose `total_count` is
    /// exactly the glanceable number the pill needs.
    public func pullRequestCount(queue: PRQueue, repo: String?, now: Date) async throws -> PRCountObservation {
        let token = try await validToken()

        var q = "is:pr is:open \(queue.rawValue):@me"
        if let repo { q += " repo:\(repo)" }

        var components = URLComponents(
            url: GitHubConfig.apiBaseURL.appendingPathComponent("search/issues"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "per_page", value: "1"),
        ]
        guard let url = components?.url else { throw GitHubAuthError.decoding }

        let request = HTTPRequest(
            url: url,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "Perch",
            ]
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw GitHubAuthError.http(status: response.status)
        }
        guard let decoded = try? JSONDecoder().decode(SearchCount.self, from: response.body) else {
            throw GitHubAuthError.decoding
        }
        return PRCountObservation(count: decoded.totalCount, observedAt: now)
    }
}

private struct SearchCount: Decodable {
    let totalCount: Int
    enum CodingKeys: String, CodingKey { case totalCount = "total_count" }
}
