import Testing
import Foundation
@testable import PerchGitHub

/// The CI "done" count. The bug this guards: GitHub reports a *finished* check
/// run under its conclusion (SUCCESS/FAILURE/NEUTRAL/SKIPPED/…), never
/// "COMPLETED", so counting COMPLETED left the bar stuck at 0/N.
@Suite struct CheckProgressTests {
    typealias Contexts = GQLSearch.Node.Contexts
    typealias StateCount = GQLSearch.Node.StateCount

    @Test func finishedRunsCountByConclusionNotCompleted() {
        // 22 checks: 5 still IN_PROGRESS, the rest finished as SUCCESS/FAILURE —
        // none are literally "COMPLETED". Done must be 17, not 0.
        let contexts = Contexts(
            totalCount: 22,
            checkRunCountsByState: [
                StateCount(state: "IN_PROGRESS", count: 5),
                StateCount(state: "SUCCESS", count: 15),
                StateCount(state: "FAILURE", count: 2),
            ],
            statusContextCountsByState: nil)
        let (total, done) = GQLSearch.checkProgress(contexts)
        #expect(total == 22)
        #expect(done == 17)
    }

    @Test func allRunningIsZeroDone() {
        let contexts = Contexts(
            totalCount: 10,
            checkRunCountsByState: [
                StateCount(state: "QUEUED", count: 4),
                StateCount(state: "IN_PROGRESS", count: 6),
            ],
            statusContextCountsByState: nil)
        #expect(GQLSearch.checkProgress(contexts).done == 0)
    }

    @Test func allFinishedIsFullDone() {
        let contexts = Contexts(
            totalCount: 3,
            checkRunCountsByState: [StateCount(state: "SUCCESS", count: 3)],
            statusContextCountsByState: nil)
        #expect(GQLSearch.checkProgress(contexts).done == 3)
    }

    @Test func legacyStatusesCountWhenNotPending() {
        // Old-style status contexts: PENDING is in-flight, SUCCESS is done.
        let contexts = Contexts(
            totalCount: 4,
            checkRunCountsByState: nil,
            statusContextCountsByState: [
                StateCount(state: "PENDING", count: 1),
                StateCount(state: "SUCCESS", count: 3),
            ])
        #expect(GQLSearch.checkProgress(contexts).done == 3)
    }

    @Test func nilContextsIsZero() {
        let (total, done) = GQLSearch.checkProgress(nil)
        #expect(total == 0 && done == 0)
    }
}

/// The unresolved-review-thread count, including the JSON decode path and the
/// nil-isResolved and truncation ("N+") edge cases.
@Suite struct UnresolvedThreadTests {
    @Test func countsOnlyExplicitlyUnresolvedAndDecodesFromJSON() throws {
        // A real reviewThreads payload: two open, one resolved, one with a null
        // isResolved (must NOT count as unresolved), plus hasNextPage.
        let json = Data("""
        {"nodes":[{"isResolved":false},{"isResolved":true},{"isResolved":false},{"isResolved":null}],
         "pageInfo":{"hasNextPage":true}}
        """.utf8)
        let threads = try JSONDecoder().decode(GQLSearch.Node.ReviewThreads.self, from: json)
        let (count, more) = GQLSearch.unresolvedThreadCount(threads)
        #expect(count == 2)     // the two false; null and true excluded
        #expect(more == true)   // truncated → caller shows "N+"
    }

    @Test func nilThreadsIsZeroAndNotTruncated() {
        let (count, more) = GQLSearch.unresolvedThreadCount(nil)
        #expect(count == 0)
        #expect(more == false)
    }

    @Test func unresolvedLabelMarksTruncation() {
        func pr(_ n: Int, more: Bool) -> PRSummary {
            PRSummary(number: 1, title: "t", repo: "o/r", url: "u", unresolvedThreads: n, moreThreads: more)
        }
        #expect(pr(3, more: false).unresolvedLabel == "3")
        #expect(pr(100, more: true).unresolvedLabel == "100+")
    }
}
