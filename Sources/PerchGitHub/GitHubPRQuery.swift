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

/// A single pull request in a queue, with enough to show + open it, plus its
/// review + merge status when fetched via GraphQL.
public struct PRSummary: Sendable, Equatable {
    public let number: Int
    public let title: String
    public let repo: String   // "owner/name"
    public let url: String
    /// GitHub `reviewDecision`: APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED / nil.
    public let reviewDecision: String?
    /// GitHub `mergeable`: MERGEABLE / CONFLICTING / UNKNOWN / nil.
    public let mergeable: String?
    public let isDraft: Bool
    /// CI checks rollup on the head commit: SUCCESS / FAILURE / ERROR / PENDING / nil.
    /// This is the "why is the pipeline running / is it green" signal.
    public let checksState: String?

    public init(number: Int, title: String, repo: String, url: String,
                reviewDecision: String? = nil, mergeable: String? = nil,
                isDraft: Bool = false, checksState: String? = nil) {
        self.number = number
        self.title = title
        self.repo = repo
        self.url = url
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.isDraft = isDraft
        self.checksState = checksState
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

    /// The queue's total plus the first `limit` items with review + merge status,
    /// via GraphQL (one request), for the panel's PR list.
    public func pullRequestList(queue: PRQueue, repo: String?, limit: Int = 8, now: Date) async throws -> PRListObservation {
        var q = "is:pr is:open \(queue.rawValue):@me"
        if let repo { q += " repo:\(repo)" }

        let gql = """
        query($q: String!, $n: Int!) {
          search(query: $q, type: ISSUE, first: $n) {
            issueCount
            nodes {
              ... on PullRequest {
                number title url isDraft reviewDecision mergeable
                repository { nameWithOwner }
                commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
              }
            }
          }
        }
        """
        let data = try await graphQL(gql, variables: ["q": q, "n": limit])
        guard let decoded = try? JSONDecoder().decode(GQLSearch.self, from: data) else {
            throw GitHubAuthError.decoding
        }
        let items = decoded.search.nodes.compactMap { node -> PRSummary? in
            guard let number = node.number, let title = node.title, let url = node.url else { return nil }
            let checks = node.commits?.nodes.first?.commit?.statusCheckRollup?.state
            return PRSummary(number: number, title: title,
                             repo: node.repository?.nameWithOwner ?? "",
                             url: url,
                             reviewDecision: node.reviewDecision,
                             mergeable: node.mergeable,
                             isDraft: node.isDraft ?? false,
                             checksState: checks)
        }
        return PRListObservation(total: decoded.search.issueCount, items: items, observedAt: now)
    }
}

private struct SearchCount: Decodable {
    let totalCount: Int
    enum CodingKeys: String, CodingKey { case totalCount = "total_count" }
}

// GraphQL response shapes (nodes are heterogeneous, so every field is optional).
private struct GQLSearch: Decodable {
    let search: Inner
    struct Inner: Decodable {
        let issueCount: Int
        let nodes: [Node]
    }
    struct Node: Decodable {
        let number: Int?
        let title: String?
        let url: String?
        let isDraft: Bool?
        let reviewDecision: String?
        let mergeable: String?
        let repository: Repo?
        let commits: Commits?
        struct Repo: Decodable { let nameWithOwner: String }
        struct Commits: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: Commit? }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String? }
    }
}
