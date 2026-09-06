import Testing
@testable import PerchCore

@Test func backoffDoublesAndCaps() {
    let b = Backoff(base: 10, cap: 300)
    #expect(b.delay(consecutiveFailures: 1) == 10)
    #expect(b.delay(consecutiveFailures: 2) == 20)
    #expect(b.delay(consecutiveFailures: 3) == 40)
    #expect(b.delay(consecutiveFailures: 4) == 80)
    #expect(b.delay(consecutiveFailures: 5) == 160)
    #expect(b.delay(consecutiveFailures: 6) == 300)   // capped
    #expect(b.delay(consecutiveFailures: 99) == 300)  // stays capped
}
