import Testing
import PerchCore
import PerchGitHub
@testable import PerchModules

@Suite struct PRTransitionsTests {
    func pr(_ n: Int, mergeable: String = "MERGEABLE", ci: String? = "SUCCESS",
            decision: String? = nil, reviews: Int = 0, comments: Int = 0) -> PRSummary {
        PRSummary(number: n, title: "PR \(n)", repo: "o/r", url: "https://x/\(n)",
                  reviewDecision: decision, mergeable: mergeable, checksState: ci,
                  reviewCount: reviews, commentCount: comments)
    }
    func detect(_ prev: [PRSummary], _ cur: [PRSummary], _ pc: Int, _ cc: Int) -> [PRChange] {
        PRTransitions.detect(previous: prev, current: cur, previousCount: pc, currentCount: cc)
    }

    // MARK: transitions

    @Test func conflictFires() {
        let c = detect([pr(1, mergeable: "MERGEABLE")], [pr(1, mergeable: "CONFLICTING")], 1, 1)
        #expect(c.map(\.kind) == [.conflicts])
        // Id is episodic: a stable prefix + a per-occurrence token, so a
        // resolve→reoccur cycle re-fires instead of being deduped forever.
        #expect(c.first?.id.hasPrefix("pr-o/r#1-conflicts-") == true)
        #expect(c.first?.phrase == "now has merge conflicts")
    }

    @Test func edgeIdsCarryAnEpisodeToken() {
        // The id ends in the per-occurrence AlertEpisode token, so the same edge
        // occurring again (a resolved-then-reintroduced conflict) gets a distinct
        // id and re-fires rather than being deduped away by the notifier.
        let c = detect([pr(1, mergeable: "MERGEABLE")], [pr(1, mergeable: "CONFLICTING")], 1, 1)
        let suffix = c.first?.id.split(separator: "-").last
        #expect(suffix.flatMap { Int($0) } != nil)   // trailing token is an epoch-second int
    }

    @Test func ciFailFires() {
        #expect(detect([pr(1, ci: "SUCCESS")], [pr(1, ci: "FAILURE")], 1, 1).map(\.kind) == [.ciFailing])
        #expect(detect([pr(1, ci: "SUCCESS")], [pr(1, ci: "ERROR")], 1, 1).map(\.kind) == [.ciFailing])
    }

    @Test func reviewDecisionFires() {
        #expect(detect([pr(1)], [pr(1, decision: "CHANGES_REQUESTED")], 1, 1).map(\.kind) == [.changesRequested])
        #expect(detect([pr(1)], [pr(1, decision: "APPROVED")], 1, 1).map(\.kind) == [.approved])
    }

    @Test func newReviewOrCommentFires() {
        #expect(detect([pr(1, reviews: 2)], [pr(1, reviews: 3)], 1, 1).map(\.kind) == [.newReviewOrComment])
        #expect(detect([pr(1, comments: 0)], [pr(1, comments: 1)], 1, 1).map(\.kind) == [.newReviewOrComment])
    }

    @Test func noChangeIsSilent() {
        #expect(detect([pr(1, reviews: 2)], [pr(1, reviews: 2)], 1, 1).isEmpty)
    }

    /// A PR with a specific head commit + whether an OTHER author pushed it + threads.
    func prc(_ n: Int, oid: String?, byOther: Bool = false, threads: Int = 0) -> PRSummary {
        PRSummary(number: n, title: "PR \(n)", repo: "o/r", url: "https://x/\(n)",
                  mergeable: "MERGEABLE", checksState: "SUCCESS",
                  threadCount: threads, headOid: oid, headByOther: byOther)
    }

    @Test func someoneElsePushingACommitFires() {
        let c = detect([prc(1, oid: "aaa")], [prc(1, oid: "bbb", byOther: true)], 1, 1)
        #expect(c.map(\.kind) == [.newCommit])
        #expect(c.first?.phrase == "new commit pushed")
    }

    @Test func yourOwnPushIsSuppressed() {
        // Head changed but not attributed to someone else → no nag (your own push,
        // or an unresolvable author — both bias to silence).
        #expect(detect([prc(1, oid: "aaa")], [prc(1, oid: "bbb", byOther: false)], 1, 1).isEmpty)
    }

    @Test func inlineThreadActivityFires() {
        // A new inline review-comment thread (no change to reviews/comments counts).
        #expect(detect([prc(1, oid: "a", threads: 1)], [prc(1, oid: "a", threads: 2)], 1, 1)
            .map(\.kind) == [.newReviewOrComment])
    }

    @Test func aFreshCommitOutranksNewComment() {
        // Both an other-author push and a comment in one poll → report the push.
        let prev = PRSummary(number: 1, title: "P", repo: "o/r", url: "u",
                             mergeable: "MERGEABLE", checksState: "SUCCESS",
                             commentCount: 0, threadCount: 0, headOid: "a")
        let cur = PRSummary(number: 1, title: "P", repo: "o/r", url: "u",
                            mergeable: "MERGEABLE", checksState: "SUCCESS",
                            commentCount: 1, threadCount: 0, headOid: "b", headByOther: true)
        #expect(detect([prev], [cur], 1, 1).map(\.kind) == [.newCommit])
    }

    @Test func onePRReportsItsMostImportantChangeOnly() {
        // Conflicts + changes-requested at once → one change, the conflict (higher).
        let c = detect([pr(1)], [pr(1, mergeable: "CONFLICTING", decision: "CHANGES_REQUESTED")], 1, 1)
        #expect(c.map(\.kind) == [.conflicts])
    }

    @Test func newPRFiresOnlyWhenQueueGrew() {
        // A genuinely new PR + the total grew → a newPR change.
        let grew = detect([pr(1)], [pr(2), pr(1)], 1, 2)
        #expect(grew.contains { $0.kind == .newPR && $0.number == 2 })
        // The NEW PR is named even when an already-known PR sorts first (activity
        // bumped it up) — attribution follows the diff, not list order.
        let bumped = detect([pr(1)], [pr(1), pr(7)], 1, 2)   // #1 known & first, #7 is the new one
        let newOnes = bumped.filter { $0.kind == .newPR }.map(\.number)
        #expect(newOnes == [7])
        // Its id carries repo + an episode token (dedups per occurrence, no cross-repo collision).
        #expect(bumped.first { $0.kind == .newPR }?.id.hasPrefix("pr-o/r#7-new-") == true)
        // Same total but a different PR in the (paged) list → NOT a false "new".
        #expect(detect([pr(1)], [pr(3)], 1, 1).isEmpty)
    }

    @Test func multiplePRsEachContributeAChange() {
        let c = detect([pr(1), pr(2)],
                       [pr(1, mergeable: "CONFLICTING"), pr(2, decision: "APPROVED")], 2, 2)
        #expect(c.count == 2)
        #expect(c.max(by: { $0.kind < $1.kind })?.kind == .conflicts)   // module picks the worst
    }
}

@Suite struct PRLabelTests {
    func pr(reviews: Int, comments: Int, decision: String? = nil) -> PRSummary {
        PRSummary(number: 1, title: "t", repo: "o/r", url: "u",
                  reviewDecision: decision, mergeable: "MERGEABLE", checksState: "SUCCESS",
                  reviewCount: reviews, commentCount: comments)
    }

    @Test func commentedInsteadOfBareOpen() {
        // A Comment review exists (no decision) → "commented", not "open".
        #expect(GitHubPRsModule.status(for: pr(reviews: 2, comments: 0)).label == "commented")
        // Only conversation comments → "N comments".
        #expect(GitHubPRsModule.status(for: pr(reviews: 0, comments: 3)).label == "3 comments")
        #expect(GitHubPRsModule.status(for: pr(reviews: 0, comments: 1)).label == "1 comment")
        // Nothing yet → still "open".
        #expect(GitHubPRsModule.status(for: pr(reviews: 0, comments: 0)).label == "open")
    }

    @Test func commentNoteShowsBesideAReviewGate() {
        // A PR that's "awaiting re-review" but has 6 comments → the note surfaces
        // the discussion the gate word hides.
        #expect(GitHubPRsModule.commentNote(for: pr(reviews: 5, comments: 6, decision: "CHANGES_REQUESTED"),
                                            reviewLabel: "awaiting re-review") == "6 comments")
        #expect(GitHubPRsModule.commentNote(for: pr(reviews: 0, comments: 1),
                                            reviewLabel: "approved") == "1 comment")
        // No comments → no note.
        #expect(GitHubPRsModule.commentNote(for: pr(reviews: 1, comments: 0),
                                            reviewLabel: "approved") == nil)
        // The label is ALREADY the exact same count → don't double it.
        #expect(GitHubPRsModule.commentNote(for: pr(reviews: 0, comments: 3),
                                            reviewLabel: "3 comments") == nil)
        // A bare "commented" (a Comment-type review) still gets the conversation
        // count — it's a different signal from the comment total.
        #expect(GitHubPRsModule.commentNote(for: pr(reviews: 2, comments: 8),
                                            reviewLabel: "commented") == "8 comments")
    }
}
