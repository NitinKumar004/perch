import Testing
import Foundation
@testable import PerchModuleKit

@Suite struct AlertEpisodeTests {
    @Test func tokenChangesAcrossSeconds() {
        let t0 = Date(timeIntervalSince1970: 1000)
        // Same second → same token (a single episode).
        #expect(AlertEpisode.token(now: t0) == AlertEpisode.token(now: t0.addingTimeInterval(0.4)))
        // A second later → a distinct token, so a later episode isn't deduped
        // away by the notifier's permanent id memory.
        #expect(AlertEpisode.token(now: t0) != AlertEpisode.token(now: t0.addingTimeInterval(1)))
    }

    @Test func tokenIsSecondsSinceEpoch() {
        #expect(AlertEpisode.token(now: Date(timeIntervalSince1970: 1234)) == 1234)
    }
}
