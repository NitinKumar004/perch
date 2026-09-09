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
    /// Total checks on the head commit (0 = none) — the denominator of "5/10".
    public let checksTotal: Int
    /// How many of those checks have finished — the numerator of "5/10", so a
    /// running pipeline shows real progress instead of a spinner.
    public let checksDone: Int
    /// Unresolved review threads on the PR — the actionable "changes to address"
    /// signal. GitHub keeps `reviewDecision` on CHANGES_REQUESTED until a
    /// reviewer formally re-reviews, so this is what tells the author whether the
    /// ball is in their court (threads to resolve) or the reviewer's (none left).
    public let unresolvedThreads: Int
    /// True when the PR has more than the fetched page of review threads (100),
    /// so `unresolvedThreads` is a floor, not exact — the UI shows "N+" rather
    /// than silently under-counting.
    public let moreThreads: Bool
    /// Total formal reviews submitted (Approve / Request-changes / Comment) — lets
    /// the UI say "commented" when someone reviewed without a decision, and lets a
    /// rising count between polls flag a NEW review.
    public let reviewCount: Int
    /// Total conversation comments on the PR — a rising count flags new discussion
    /// even when nobody submitted a formal review.
    public let commentCount: Int
    /// Total review threads (resolved + unresolved) on the fetched page. A rising
    /// count means a NEW inline code comment / discussion thread — feedback that a
    /// top-level `commentCount` doesn't capture, so the "new activity" alert catches
    /// inline review comments too. Capped at the fetched page (first: 100); beyond
    /// 100 it plateaus — a silent ceiling only very high-traffic PRs ever hit.
    public let threadCount: Int
    /// The head commit's SHA. A change between polls means someone PUSHED a new
    /// commit — the one PR event that leaves no other trace (no CI break, no
    /// conflict, no comment), so it's tracked explicitly to alert on a push.
    public let headOid: String?
    /// True ONLY when the head commit is positively attributable to someone who is
    /// NOT the viewer. A "new commit" alert fires solely on this, so it biases to
    /// SILENCE: an unattributable push (author email not linked to a GitHub
    /// account — common on your own machine) never nags you as if it were someone
    /// else's. The signal you want — a teammate pushing to a PR you watch — always
    /// resolves to a login, so it still fires.
    public let headByOther: Bool

    public init(number: Int, title: String, repo: String, url: String,
                reviewDecision: String? = nil, mergeable: String? = nil,
                isDraft: Bool = false, checksState: String? = nil,
                checksTotal: Int = 0, checksDone: Int = 0,
                unresolvedThreads: Int = 0, moreThreads: Bool = false,
                reviewCount: Int = 0, commentCount: Int = 0,
                threadCount: Int = 0, headOid: String? = nil, headByOther: Bool = false) {
        self.number = number
        self.title = title
        self.repo = repo
        self.url = url
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.isDraft = isDraft
        self.checksState = checksState
        self.checksTotal = checksTotal
        self.checksDone = checksDone
        self.unresolvedThreads = unresolvedThreads
        self.moreThreads = moreThreads
        self.reviewCount = reviewCount
        self.commentCount = commentCount
        self.threadCount = threadCount
        self.headOid = headOid
        self.headByOther = headByOther
    }

    /// A count that honestly says "N+" when we only saw the first page of threads.
    public var unresolvedLabel: String { moreThreads ? "\(unresolvedThreads)+" : "\(unresolvedThreads)" }

    /// Approved, CI green, definitively mergeable, not a draft → ready to merge.
    /// The positive end-state worth surfacing so you know a PR is good to land.
    /// Requires mergeable == MERGEABLE explicitly: GitHub's `UNKNOWN` means "still
    /// computing" (common right after a push), and `!= CONFLICTING` would let that
    /// through as a false green that flips to CONFLICTING moments later.
    public var isReadyToMerge: Bool {
        reviewDecision == "APPROVED"
            && checksState == "SUCCESS"
            && mergeable == "MERGEABLE"
            && !isDraft
    }
}

/// A queue's total plus the first page of items, stamped with observation time.
public struct PRListObservation: Sendable, Equatable {
    public let total: Int
    public let items: [PRSummary]
    public let observedAt: Date

    public init(total: Int, items: [PRSummary], observedAt: Date) {
        self.total = total
        self.items = items
        self.observedAt = observedAt
    }
}

/// Which pull-request queue to count.
public enum PRQueue: String, Sendable {
    /// Everything you're a reviewer on — the union of `reviewRequested` and
    /// `reviewedBy`. GitHub has no single qualifier for this, so it's fetched as
    /// two queries and merged client-side; it's never sent as one `x:@me` term.
    /// This is the intuitive "my reviews" list: PRs waiting on you AND ones you've
    /// already reviewed, together.
    case reviewing = "reviewing"
    /// PRs where your review has been requested but you HAVEN'T reviewed yet
    /// (the ball is in your court). A PR leaves this queue the moment you submit
    /// a review — that's `reviewedBy`, not this.
    case reviewRequested = "review-requested"
    /// PRs you have already reviewed (still open). What you'd expect "my reviews"
    /// to show after you've actually reviewed them.
    case reviewedBy = "reviewed-by"
    /// PRs you opened.
    case authored = "author"
}

extension GitHubAPIClient {
    /// Build a PR search query, scoped to zero, one, or many repos. GitHub search
    /// accepts multiple `repo:` qualifiers (OR'd), so several repos combine into a
    /// single count + a single merged list — no double-counting, one request.
    /// An empty `repos` searches every repo the user can access.
    static func prQuery(queue: PRQueue, repos: [String]) -> String {
        // `.reviewing` is a client-side UNION of two queries — it's never a single
        // GitHub qualifier. It must be intercepted before it reaches here (see
        // GitHubPRsModule.observe); if a future caller forgets, fail loudly in debug
        // and fall back to a VALID term in release so we never emit `reviewing:@me`.
        assert(queue != .reviewing, "prQuery called with .reviewing — resolve the union upstream, don't build a single query for it")
        let qualifier = (queue == .reviewing ? PRQueue.reviewRequested : queue).rawValue
        var q = "is:pr is:open \(qualifier):@me"
        // "Reviewed by me" is a REVIEWER queue: other people's PRs I reviewed, not
        // my own. GitHub's `reviewed-by` counts commenting on your own PR as a
        // review, so exclude PRs I authored — otherwise my own PRs leak in.
        if queue == .reviewedBy { q += " -author:@me" }
        for repo in repos where !repo.isEmpty { q += " repo:\(repo)" }
        return q
    }

    /// Count the authenticated user's open PRs in `queue`, across `repos`
    /// (empty = all accessible repos). `total_count` is the glanceable number.
    public func pullRequestCount(queue: PRQueue, repos: [String], now: Date) async throws -> PRCountObservation {
        let token = try await validToken()

        let q = Self.prQuery(queue: queue, repos: repos)

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
    /// via GraphQL (one request), across `repos` (empty = all accessible repos).
    public func pullRequestList(queue: PRQueue, repos: [String], limit: Int = 8, now: Date) async throws -> PRListObservation {
        let q = Self.prQuery(queue: queue, repos: repos)

        let gql = """
        query($q: String!, $n: Int!) {
          viewer { login }
          search(query: $q, type: ISSUE, first: $n) {
            issueCount
            nodes {
              ... on PullRequest {
                number title url isDraft reviewDecision mergeable
                repository { nameWithOwner }
                reviews(first: 0) { totalCount }
                comments(first: 0) { totalCount }
                reviewThreads(first: 100) { nodes { isResolved } pageInfo { hasNextPage } }
                commits(last: 1) { nodes { commit {
                  oid
                  author { user { login } }
                  statusCheckRollup {
                    state
                    contexts(first: 100) {
                      totalCount
                      checkRunCountsByState { state count }
                      statusContextCountsByState { state count }
                    }
                  }
                } } }
              }
            }
          }
        }
        """
        let data = try await graphQL(gql, variables: ["q": q, "n": limit])
        guard let decoded = try? JSONDecoder().decode(GQLSearch.self, from: data) else {
            throw GitHubAuthError.decoding
        }
        let viewerLogin = decoded.viewer?.login
        let items = decoded.search.nodes.compactMap { node -> PRSummary? in
            guard let number = node.number, let title = node.title, let url = node.url else { return nil }
            let headCommit = node.commits?.nodes.first?.commit
            let rollup = headCommit?.statusCheckRollup
            let headByOther = GQLSearch.headByOther(author: headCommit?.author?.user?.login, viewer: viewerLogin)
            let (total, done) = GQLSearch.checkProgress(rollup?.contexts)
            let (unresolved, moreThreads) = GQLSearch.unresolvedThreadCount(node.reviewThreads)
            return PRSummary(number: number, title: title,
                             repo: node.repository?.nameWithOwner ?? "",
                             url: url,
                             reviewDecision: node.reviewDecision,
                             mergeable: node.mergeable,
                             isDraft: node.isDraft ?? false,
                             checksState: rollup?.state,
                             checksTotal: total, checksDone: done,
                             unresolvedThreads: unresolved, moreThreads: moreThreads,
                             reviewCount: node.reviews?.totalCount ?? 0,
                             commentCount: node.comments?.totalCount ?? 0,
                             threadCount: node.reviewThreads?.nodes.count ?? 0,
                             headOid: headCommit?.oid, headByOther: headByOther)
        }
        return PRListObservation(total: decoded.search.issueCount, items: items, observedAt: now)
    }
}

private struct SearchCount: Decodable {
    let totalCount: Int
    enum CodingKeys: String, CodingKey { case totalCount = "total_count" }
}

// GraphQL response shapes (nodes are heterogeneous, so every field is optional).
// Internal (not private) so `checkProgress` — the CI done-count logic — is unit
// testable; it's the one piece with a real classification bug worth guarding.
struct GQLSearch: Decodable {
    let search: Inner
    let viewer: Viewer?
    struct Viewer: Decodable { let login: String? }
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
        let reviewThreads: ReviewThreads?
        let reviews: CountOnly?
        let comments: CountOnly?
        struct Repo: Decodable { let nameWithOwner: String }
        struct CountOnly: Decodable { let totalCount: Int }
        struct ReviewThreads: Decodable {
            let nodes: [Thread]
            let pageInfo: PageInfo?
            struct Thread: Decodable { let isResolved: Bool? }
            struct PageInfo: Decodable { let hasNextPage: Bool? }
        }
        struct Commits: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: Commit? }
        struct Commit: Decodable {
            let oid: String?
            let author: CommitAuthor?
            let statusCheckRollup: Rollup?
        }
        struct CommitAuthor: Decodable { let user: AuthorUser?; struct AuthorUser: Decodable { let login: String? } }
        struct Rollup: Decodable {
            let state: String?
            let contexts: Contexts?
        }
        struct Contexts: Decodable {
            let totalCount: Int
            let checkRunCountsByState: [StateCount]?
            let statusContextCountsByState: [StateCount]?
        }
        struct StateCount: Decodable { let state: String; let count: Int }
    }

    /// True only when the head commit is positively attributable to someone OTHER
    /// than the viewer — both logins must be known and differ. An unresolved author
    /// (nil `user.login`, e.g. an email not linked to a GitHub account) or a missing
    /// viewer yields `false`, so a "new commit" alert biases to silence rather than
    /// risk nagging you about your own push.
    static func headByOther(author: String?, viewer: String?) -> Bool {
        guard let author, let viewer else { return false }
        return author != viewer
    }

    /// Reduce the rollup's per-state counts to (total, finished) so a running
    /// pipeline can read "5/22" and climb.
    ///
    /// Counting finished runs by state == "COMPLETED" is WRONG: GitHub's
    /// `checkRunCountsByState` reports a finished run under its *conclusion*
    /// (SUCCESS / FAILURE / NEUTRAL / SKIPPED / CANCELLED / TIMED_OUT / …), never
    /// "COMPLETED" — so that filter counts ~nothing and the bar sits at 0/22 then
    /// jumps to pass/fail. Instead count "done" as total minus whatever is still
    /// in flight (the handful of genuinely-pending states).
    static func checkProgress(_ contexts: Node.Contexts?) -> (total: Int, done: Int) {
        guard let contexts else { return (0, 0) }
        let runsInFlight = (contexts.checkRunCountsByState ?? [])
            .filter { runningStates.contains($0.state) }
            .reduce(0) { $0 + $1.count }
        let statusesInFlight = (contexts.statusContextCountsByState ?? [])
            .filter { $0.state == "PENDING" || $0.state == "EXPECTED" }
            .reduce(0) { $0 + $1.count }
        let done = contexts.totalCount - runsInFlight - statusesInFlight
        return (contexts.totalCount, Swift.max(0, Swift.min(contexts.totalCount, done)))
    }

    /// Check-run states that mean "not finished yet". Everything else (a
    /// conclusion) counts as done.
    private static let runningStates: Set<String> = ["QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"]

    /// Count unresolved review threads from the fetched page, and whether there
    /// were more than that page (so the caller can show "N+" honestly). A thread
    /// with a null `isResolved` is treated as NOT-unresolved (conservative — we
    /// only badge what GitHub clearly says is open).
    static func unresolvedThreadCount(_ threads: Node.ReviewThreads?) -> (count: Int, more: Bool) {
        let count = (threads?.nodes ?? []).filter { $0.isResolved == false }.count
        return (count, threads?.pageInfo?.hasNextPage ?? false)
    }
}
