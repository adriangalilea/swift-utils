import Testing
import os

@testable import Grant

enum Why: Equatable { case off, absent, failing }

private func claim() -> Claim<Why> {
    Claim(whenFailing: .failing, log: Logger(subsystem: "test", category: "claim"))
}

// The epistemics, pinned: a readable switch is a claim whose off-reason
// the consumer names, a live capability is present-tense proof, a past
// success is a witness of the past, and an unreadable switch is unknown -
// never off, never good.
@Test func readableSwitchClaims() {
    let c = claim()
    c.evaluate(intent: .off(.off), live: false)
    #expect(c.verdict == .impossible(.off))
    c.evaluate(intent: .off(.absent), live: false)
    #expect(c.verdict == .impossible(.absent))
    c.evaluate(intent: .on, live: false)
    #expect(c.verdict == .unproven)
    c.observe(.succeeded)
    #expect(c.verdict == .capable)
    c.observe(.failed("mount refused"))
    #expect(c.verdict == .impossible(.failing))
}

@Test func unreadableSwitchIsUnknown() {
    let c = claim()
    c.evaluate(intent: .unreadable, live: false)
    #expect(c.verdict == .unknown)
    // A success proves the moment, and only the moment.
    c.observe(.succeeded)
    #expect(c.verdict == .capable)
    c.evaluate(intent: .unreadable, live: false)
    #expect(c.verdict == .unknown)
    // Live right now is present-tense proof.
    c.evaluate(intent: .unreadable, live: true)
    #expect(c.verdict == .capable)
    // A failure under an unreadable switch is still a failure.
    c.observe(.failed("mount refused"))
    c.evaluate(intent: .unreadable, live: false)
    #expect(c.verdict == .impossible(.failing))
}
