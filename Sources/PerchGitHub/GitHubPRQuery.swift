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

/// A single pull request in a queue, with enough to show + open it.
public struct PRSummary: Sendable, Equatable {
    public let number: Int
    public let title: String
    public let repo: String   // "owner/name"
    public let url: String

    public init(number: Int, title: String, repo: String, url: String) {
        self.number = number
        self.title = title
        self.repo = repo
        self.url = url
    }
}

/// A queue's total plus the first page of items, stamped with observation time.
public struct PRListObservation: Sendable, Equatable {
    public let total: Int
    public let items: [PRSummary]
    public let observedAt: Date
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

    /// The queue's total plus the first `limit` items (title + link), for the
    /// panel's PR list.
    public func pullRequestList(queue: PRQueue, repo: String?, limit: Int = 8, now: Date) async throws -> PRListObservation {
        let token = try await validToken()

        var q = "is:pr is:open \(queue.rawValue):@me"
        if let repo { q += " repo:\(repo)" }

        var components = URLComponents(
            url: GitHubConfig.apiBaseURL.appendingPathComponent("search/issues"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "per_page", value: String(limit)),
            URLQueryItem(name: "sort", value: "updated"),
        ]
        guard let url = components?.url else { throw GitHubAuthError.decoding }

        let request = HTTPRequest(
            url: url, method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "Perch",
            ]
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else { throw GitHubAuthError.http(status: response.status) }
        guard let decoded = try? JSONDecoder().decode(SearchResult.self, from: response.body) else {
            throw GitHubAuthError.decoding
        }

        let items = decoded.items.map { item -> PRSummary in
            // repository_url looks like https://api.github.com/repos/owner/name
            let repoName = item.repositoryUrl.components(separatedBy: "/repos/").last ?? ""
            return PRSummary(number: item.number, title: item.title, repo: repoName, url: item.htmlUrl)
        }
        return PRListObservation(total: decoded.totalCount, items: items, observedAt: now)
    }
}

private struct SearchCount: Decodable {
    let totalCount: Int
    enum CodingKeys: String, CodingKey { case totalCount = "total_count" }
}

private struct SearchResult: Decodable {
    let totalCount: Int
    let items: [Item]
    enum CodingKeys: String, CodingKey { case totalCount = "total_count", items }

    struct Item: Decodable {
        let number: Int
        let title: String
        let htmlUrl: String
        let repositoryUrl: String
        enum CodingKeys: String, CodingKey {
            case number, title
            case htmlUrl = "html_url"
            case repositoryUrl = "repository_url"
        }
    }
}
