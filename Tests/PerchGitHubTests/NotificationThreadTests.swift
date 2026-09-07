import Testing
import Foundation
@testable import PerchGitHub

@Suite struct NotificationThreadTests {
    func thread(type: String, apiURL: String?, repo: String = "acme/api") -> NotificationThread {
        NotificationThread(id: "1", reason: "mention", title: "t", repo: repo,
                           subjectType: type, apiURL: apiURL, updatedAt: Date())
    }

    @Test func pullRequestApiUrlMapsToHtmlPull() {
        // GitHub gives an API url on a notification subject, never an html one.
        let t = thread(type: "PullRequest", apiURL: "https://api.github.com/repos/acme/api/pulls/88")
        #expect(t.htmlURL == "https://github.com/acme/api/pull/88")
    }

    @Test func issueApiUrlMapsToHtmlIssues() {
        let t = thread(type: "Issue", apiURL: "https://api.github.com/repos/acme/api/issues/123")
        #expect(t.htmlURL == "https://github.com/acme/api/issues/123")
    }

    @Test func unmappableSubjectFallsBackToRepoPage() {
        // A Commit/Release/Discussion (no issue/pull number) → the repo page,
        // never a dead API link.
        let commit = thread(type: "Commit", apiURL: "https://api.github.com/repos/acme/api/commits/deadbeef")
        #expect(commit.htmlURL == "https://github.com/acme/api")
        let none = thread(type: "Release", apiURL: nil)
        #expect(none.htmlURL == "https://github.com/acme/api")
    }

    @Test func trailingNumberParses() {
        #expect(NotificationThread.trailingNumber(after: "/pulls/", in: ".../pulls/88") == 88)
        #expect(NotificationThread.trailingNumber(after: "/issues/", in: ".../issues/7/comments") == 7)
        #expect(NotificationThread.trailingNumber(after: "/pulls/", in: ".../issues/7") == nil)
    }
}
