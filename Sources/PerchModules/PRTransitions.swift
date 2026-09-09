import Foundation
import PerchGitHub
import PerchModuleKit

/// One meaningful change in a watched PR between two polls — so Perch can *tell*
/// you when a PR breaks or gets feedback, not just when a new one arrives.
public struct PRChange: Sendable, Equatable {
    /// Ordered by how much it wants your attention (higher = more urgent). The
    /// module surfaces the single highest-priority change and summarises the rest.
    public enum Kind: Int, Sendable, Comparable {
        case newReviewOrComment = 0   // someone looked at it
        case newCommit          = 1   // someone else pushed to it
        case newPR              = 2   // a new PR landed in your queue
        case approved           = 3
        case changesRequested   = 4
        case ciFailing          = 5
        case conflicts          = 6   // your branch no longer merges
        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }
    public let kind: Kind
    public let number: Int
    public let title: String
    public let url: String
    /// The human phrase for the change ("now has merge conflicts").
    public let phrase: String
    /// A stable notification id: keyed so the SAME state never re-nags, but a
    /// genuinely new change (a 4th review, a fresh conflict) does.
    public let id: String
}

/// Detects PR changes between two observations. Pure — no network, no UI — so
/// the exact rules are unit-testable. Matches PRs by `repo#number`; a PR not seen
/// in the previous poll is only "new" when the queue actually grew (so a list
/// reshuffle never invents a change).
public enum PRTransitions {
    public static func detect(previous: [PRSummary], current: [PRSummary],
                              previousCount: Int, currentCount: Int) -> [PRChange] {
        let byKey = Dictionary(previous.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [PRChange] = []
        for pr in current {
            if let old = byKey[key(pr)], let change = change(from: old, to: pr) {
                changes.append(change)
            }
        }
        // Brand-new PRs in your queue — only when the total genuinely grew (so a
        // list reshuffle never invents one). Name the PRs that are ACTUALLY new
        // (not in the previous set), not just current.first — the search list is
        // ordered by activity, so the first item is often an already-known PR.
        // Each carries repo + an episode token so it dedups per occurrence but a
        // different repo's same-numbered PR (or a re-entry) can't be swallowed.
        if currentCount > previousCount {
            for pr in current where byKey[key(pr)] == nil {
                changes.append(PRChange(kind: .newPR, number: pr.number, title: pr.title,
                                        url: pr.url, phrase: "waiting on your review",
                                        id: "pr-\(key(pr))-new-\(AlertEpisode.token())"))
            }
        }
        return changes
    }

    /// The single most important change for one PR between polls, or nil.
    ///
    /// Every change is an *episode*: `detect` already fires only on the rising
    /// edge (new state != old state), and the id carries a fresh
    /// `AlertEpisode.token()` per edge — so a resolve→reoccur cycle (a conflict
    /// cleared then reintroduced by new commits, a lost-then-regained approval)
    /// alerts EACH time, instead of being swallowed by the notifier's permanent
    /// id-dedup. This is the same episode discipline the vitals/thermal/swap/disk
    /// modules use; nothing here re-rolls it.
    static func change(from old: PRSummary, to pr: PRSummary) -> PRChange? {
        func make(_ kind: PRChange.Kind, _ phrase: String, _ tag: String) -> PRChange {
            PRChange(kind: kind, number: pr.number, title: pr.title, url: pr.url,
                     phrase: phrase, id: "pr-\(key(pr))-\(tag)-\(AlertEpisode.token())")
        }
        if pr.mergeable == "CONFLICTING", old.mergeable != "CONFLICTING" {
            return make(.conflicts, "now has merge conflicts", "conflicts")
        }
        if isFailing(pr.checksState), !isFailing(old.checksState) {
            return make(.ciFailing, "CI is failing", "ci-fail")
        }
        if pr.reviewDecision == "CHANGES_REQUESTED", old.reviewDecision != "CHANGES_REQUESTED" {
            return make(.changesRequested, "changes requested", "changes")
        }
        if pr.reviewDecision == "APPROVED", old.reviewDecision != "APPROVED" {
            return make(.approved, "approved", "approved")
        }
        // Someone ELSE pushed a new commit — the one event with no other trace.
        // Fires ONLY on a positively-attributed other-author push (headByOther), so
        // your own pushes — and unattributable ones — never nag you.
        if let oldOid = old.headOid, let newOid = pr.headOid, oldOid != newOid, pr.headByOther {
            return make(.newCommit, "new commit pushed", "commit")
        }
        // New review activity: a formal review, a conversation comment, OR a new
        // inline code-comment thread (threadCount) — so inline feedback that never
        // touches the top-level comment count still alerts.
        if pr.reviewCount > old.reviewCount || pr.commentCount > old.commentCount
            || pr.threadCount > old.threadCount {
            return make(.newReviewOrComment, "new review activity", "activity")
        }
        return nil
    }

    private static func key(_ pr: PRSummary) -> String { "\(pr.repo)#\(pr.number)" }
    private static func isFailing(_ state: String?) -> Bool { state == "FAILURE" || state == "ERROR" }
}
