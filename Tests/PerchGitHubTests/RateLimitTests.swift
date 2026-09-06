import Testing
import Foundation
@testable import PerchGitHub

@Test func rateLimitParsesHeaders() {
    let reset = Date(timeIntervalSince1970: 2_000_000_000)
    let response = HTTPResponse(status: 200, body: Data(), headers: [
        "X-RateLimit-Remaining": "42",
        "X-RateLimit-Reset": "2000000000",
    ])
    let limit = RateLimit.from(response)
    #expect(limit?.remaining == 42)
    #expect(limit?.reset == reset)
    // Missing headers → nil (e.g. a 304).
    #expect(RateLimit.from(HTTPResponse(status: 304, body: Data())) == nil)
}

@Test func rateLimitThrottleOnlyWhenLow() {
    let now = Date()
    let plenty = RateLimit(remaining: 500, reset: now.addingTimeInterval(600))
    #expect(plenty.throttleDelay(now: now) == 0)

    let low = RateLimit(remaining: 3, reset: now.addingTimeInterval(120))
    #expect(low.throttleDelay(now: now) == 120)

    // Past the reset → clamped to 0, not negative.
    let expired = RateLimit(remaining: 0, reset: now.addingTimeInterval(-30))
    #expect(expired.throttleDelay(now: now) == 0)
}

@Test func rateLimitGateSharesLatest() async {
    let gate = RateLimitGate()
    #expect(await gate.throttleDelay() == 0)          // no reading yet
    await gate.record(nil)                            // ignored
    #expect(await gate.remaining() == nil)
    let now = Date()
    await gate.record(RateLimit(remaining: 2, reset: now.addingTimeInterval(60)))
    #expect(await gate.remaining() == 2)
    #expect(await gate.throttleDelay(now: now) == 60)
}
