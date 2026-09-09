import Foundation

/// How a build looks once we've classified GitHub's `status` + `conclusion`
/// into something the UI cares about.
public enum RunState: String, Sendable, Equatable {
    case running
    case passing
    case failing
    case neutral   // cancelled / skipped / manual — cost no signal either way
    case unknown
}

/// One observation of a repo's latest build, stamped with GitHub's own
/// `updated_at` — the version the accuracy engine orders by. Carries enough
/// detail for the panel: the workflow name, branch, short SHA, and a run URL.
public struct BuildObservation: Sendable, Equatable {
    public let state: RunState
    public let updatedAt: Date
    public let url: String
    public let workflowName: String
    /// GitHub's per-workflow run number (the "#1636"), so the panel names the
    /// EXACT run — not just "CI", which is ambiguous when a repo runs several
    /// workflows on one commit.
    public let runNumber: Int
    /// The run's display title (usually the PR/commit title, e.g. "v2.11.0") — the
    /// human "what build ran".
    public let displayTitle: String
    public let branch: String
    public let shortSHA: String
    public let durationSeconds: Int
}

/// Authenticated read-only calls to the GitHub REST API. Every call asks
/// `GitHubAuth` for a valid token first (which refreshes silently as needed),
/// so callers never think about auth.
public struct GitHubAPIClient: Sendable {
    private let http: any HTTPClient
    private let auth: GitHubAuth
    /// Shared rate-limit record — every call reports its headers here so pollers
    /// can back off together before GitHub starts returning 403s.
    public let rateLimit: RateLimitGate

    public init(http: any HTTPClient = URLSessionHTTPClient(), auth: GitHubAuth,
                rateLimit: RateLimitGate = RateLimitGate()) {
        self.http = http
        self.auth = auth
        self.rateLimit = rateLimit
    }

    /// The HTTP transport, for other query files in this module to share.
    var transport: any HTTPClient { http }

    /// A currently-valid access token (refreshing if needed), shared by all
    /// query files in this module.
    func validToken() async throws -> String { try await auth.validAccessToken() }

    /// Run a GraphQL query and return the raw `data` object's bytes. Throws
    /// `.http` on a non-2xx and `.decoding` if the response carries GraphQL
    /// errors instead of data.
    func graphQL(_ query: String, variables: [String: Any]) async throws -> Data {
        let token = try await validToken()
        let payload: [String: Any] = ["query": query, "variables": variables]
        let body = try JSONSerialization.data(withJSONObject: payload)

        let request = HTTPRequest(
            url: GitHubConfig.apiBaseURL.appendingPathComponent("graphql"),
            method: "POST",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/vnd.github+json",
                "User-Agent": "Perch",
                "Content-Type": "application/json",
            ],
            body: body
        )
        let response = try await http.send(request)
        await rateLimit.record(RateLimit.from(response))
        guard (200..<300).contains(response.status) else {
            throw GitHubAuthError.http(status: response.status)
        }
        guard let root = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw GitHubAuthError.decoding
        }
        // GraphQL errors arrive as `{"errors":[…],"data":null}`. JSON null
        // deserializes to `NSNull`, NOT Swift nil — so `root["data"] == nil` is
        // false and the old guards fell through to `JSONSerialization.data(
        // withJSONObject: NSNull())`, which raises an UNCATCHABLE ObjC exception
        // and aborts the process. Reject any non-dictionary `data` (null/scalar)
        // as a decode error instead.
        guard let data = root["data"], JSONSerialization.isValidJSONObject(data) else {
            throw GitHubAuthError.decoding
        }
        return try JSONSerialization.data(withJSONObject: data)
    }

    /// The result of a conditional build fetch: unchanged (a free 304), or a
    /// fresh observation plus the new ETag to send next time.
    public enum BuildFetch: Sendable {
        case notModified
        case ok(BuildObservation?, etag: String?)
        /// Pinned to a workflow, but its run wasn't in the fetched window (other
        /// workflows ran more recently). Distinct from `.ok(nil)` — the caller must
        /// KEEP the last-known build, not wipe it to "no runs".
        case pinnedAbsent(etag: String?)
    }

    /// The latest Actions run for `branch`, sent conditionally with `etag`.
    /// A 304 (unchanged) is returned as `.notModified` and — when authenticated —
    /// does not count against the REST rate limit.
    public func latestBuild(owner: String, repo: String, branch: String,
                            workflow: String = "", etag: String?) async throws -> BuildFetch {
        let token = try await auth.validAccessToken()

        // A blank branch (or "*") means "any branch": omit the filter so GitHub
        // returns the latest run across every branch — handy for a PR opened from
        // any branch. When pinned to a workflow we fetch a small page and pick that
        // workflow's latest run client-side (the runs endpoint can't filter by
        // workflow name), otherwise one run is enough.
        let anyBranch = branch.isEmpty || branch == "*"
        let wanted = workflow.trimmingCharacters(in: .whitespaces)
        let pinned = !wanted.isEmpty
        // Build the URL via URLComponents so the query string is a real query,
        // not percent-encoded into the path (which drops the branch filter). When
        // pinned we fetch a wide page (50) and pick that workflow's latest run
        // client-side, since the runs endpoint can't filter by workflow name.
        var components = URLComponents(
            url: GitHubConfig.apiBaseURL.appendingPathComponent("repos/\(owner)/\(repo)/actions/runs"),
            resolvingAgainstBaseURL: false
        )
        var query = [URLQueryItem(name: "per_page", value: pinned ? "50" : "1")]
        if !anyBranch { query.append(URLQueryItem(name: "branch", value: branch)) }
        components?.queryItems = query
        guard let url = components?.url else { throw GitHubAuthError.decoding }

        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Perch",
        ]
        if let etag { headers["If-None-Match"] = etag }

        let response = try await http.send(HTTPRequest(url: url, method: "GET", headers: headers))
        await rateLimit.record(RateLimit.from(response))
        if response.status == 304 { return .notModified }
        guard (200..<300).contains(response.status) else {
            throw GitHubAuthError.http(status: response.status)
        }
        let newEtag = response.header("ETag")
        guard let decoded = try? Self.decoder.decode(RunsResponse.self, from: response.body) else {
            throw GitHubAuthError.decoding
        }
        // Pinned to a workflow → the latest run whose name matches (trimmed,
        // case-insensitive so a copy-pasted "ci " still matches "CI"); else the
        // newest run of any workflow.
        if pinned {
            guard let run = decoded.workflowRuns.first(where: {
                $0.name?.caseInsensitiveCompare(wanted) == .orderedSame
            }) else {
                // Not in the window — keep the last-known build rather than wiping.
                return .pinnedAbsent(etag: newEtag)
            }
            return .ok(Self.buildObservation(run, fallbackBranch: branch), etag: newEtag)
        }
        guard let run = decoded.workflowRuns.first else { return .ok(nil, etag: newEtag) }
        return .ok(Self.buildObservation(run, fallbackBranch: branch), etag: newEtag)
    }

    /// Map one Actions run to a `BuildObservation` — the one place the run→panel
    /// shape lives, shared by the pinned and newest-run paths.
    private static func buildObservation(_ run: Run, fallbackBranch: String) -> BuildObservation {
        let duration = max(0, Int(run.updatedAt.timeIntervalSince(run.runStartedAt ?? run.updatedAt)))
        return BuildObservation(
            state: run.runState,
            updatedAt: run.updatedAt,
            url: run.htmlUrl,
            workflowName: run.name ?? "workflow",
            runNumber: run.runNumber ?? 0,
            displayTitle: run.displayTitle ?? "",
            branch: run.headBranch ?? fallbackBranch,
            shortSHA: String((run.headSha ?? "").prefix(7)),
            durationSeconds: duration
        )
    }

    // MARK: - Notifications

    public enum NotificationsFetch: Sendable {
        case notModified
        /// `truncated` is true when GitHub had more than the fetched page (50) of
        /// unread threads (a `rel="next"` Link), so the count is a floor.
        case ok([NotificationThread], etag: String?, truncated: Bool)
    }

    /// The user's unread notification threads, sent conditionally with `etag`.
    /// A 304 is returned as `.notModified` and doesn't count against the poll
    /// rate limit. 50 is GitHub's max page size for this endpoint; when more
    /// exist, the `Link` header carries `rel="next"` and we flag truncation.
    public func notifications(etag: String?) async throws -> NotificationsFetch {
        let token = try await auth.validAccessToken()
        var components = URLComponents(
            url: GitHubConfig.apiBaseURL.appendingPathComponent("notifications"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "per_page", value: "50")]  // unread only (default)
        guard let url = components?.url else { throw GitHubAuthError.decoding }

        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Perch",
        ]
        if let etag { headers["If-None-Match"] = etag }

        let response = try await http.send(HTTPRequest(url: url, method: "GET", headers: headers))
        await rateLimit.record(RateLimit.from(response))
        if response.status == 304 { return .notModified }
        guard (200..<300).contains(response.status) else {
            throw GitHubAuthError.http(status: response.status)
        }
        let newEtag = response.header("ETag")
        guard let decoded = try? Self.decoder.decode([NotificationWire].self, from: response.body) else {
            throw GitHubAuthError.decoding
        }
        let threads = decoded.map { w in
            NotificationThread(
                id: w.id,
                reason: w.reason,
                title: w.subject.title,
                repo: w.repository.fullName,
                subjectType: w.subject.type,
                apiURL: w.subject.url,
                updatedAt: w.updatedAt)
        }
        // GitHub paginates via the Link header; a rel="next" means there are more
        // unread threads than this page, so the count is a floor.
        let truncated = response.header("Link")?.contains("rel=\"next\"") ?? false
        return .ok(threads, etag: newEtag, truncated: truncated)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// One unread notification thread — the "GitHub bell" surfaced in the notch.
public struct NotificationThread: Sendable, Equatable {
    public let id: String
    /// GitHub's `reason`: mention, review_requested, assign, ci_activity, …
    public let reason: String
    public let title: String
    public let repo: String            // "owner/name"
    public let subjectType: String     // "PullRequest", "Issue", "Commit", …
    public let apiURL: String?         // subject.url (an API url; convert to open)
    public let updatedAt: Date

    public init(id: String, reason: String, title: String, repo: String,
                subjectType: String, apiURL: String?, updatedAt: Date) {
        self.id = id
        self.reason = reason
        self.title = title
        self.repo = repo
        self.subjectType = subjectType
        self.apiURL = apiURL
        self.updatedAt = updatedAt
    }

    /// A browser URL to open this notification. GitHub gives no `html_url` on a
    /// notification subject, so map it: the authoritative `subjectType` picks the
    /// path (PullRequest → /pull/N, Issue → /issues/N) and the number comes from
    /// the API url. Anything else falls back to the repo page (never a dead link).
    public var htmlURL: String {
        let repoPage = "\(GitHubConfig.htmlBaseURL)/\(repo)"
        guard let api = apiURL,
              let n = Self.trailingNumber(after: "/pulls/", in: api)
                   ?? Self.trailingNumber(after: "/issues/", in: api) else { return repoPage }
        switch subjectType {
        case "PullRequest": return "\(repoPage)/pull/\(n)"
        case "Issue":       return "\(repoPage)/issues/\(n)"
        default:            return repoPage
        }
    }

    /// The number segment immediately after `marker` in `url`, or nil.
    static func trailingNumber(after marker: String, in url: String) -> Int? {
        guard let range = url.range(of: marker) else { return nil }
        let tail = url[range.upperBound...].prefix { $0.isNumber }
        return Int(tail)
    }
}

private struct NotificationWire: Decodable {
    let id: String
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repo
    struct Subject: Decodable { let title: String; let url: String?; let type: String }
    struct Repo: Decodable { let fullName: String }
}

// MARK: - Wire shapes

private struct RunsResponse: Decodable {
    let workflowRuns: [Run]
}

private struct Run: Decodable {
    let status: String?
    let conclusion: String?
    let updatedAt: Date
    let htmlUrl: String
    let name: String?
    let runNumber: Int?
    let displayTitle: String?
    let headBranch: String?
    let headSha: String?
    let runStartedAt: Date?

    /// Collapse GitHub's two-field lifecycle into one `RunState`.
    var runState: RunState {
        guard status == "completed" else { return .running } // queued/in_progress/waiting/…
        switch conclusion {
        case "success":
            return .passing
        case "failure", "timed_out", "startup_failure":
            return .failing
        case "cancelled", "skipped", "neutral", "stale", "action_required":
            return .neutral
        default:
            return .unknown
        }
    }
}
