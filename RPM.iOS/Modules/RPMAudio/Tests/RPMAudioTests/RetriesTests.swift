import Testing
@testable import RPMAudio

/// How many goes one track gets.
///
/// The limit is a bound on attempts. A stream that dropped gets another attempt. A file that is
/// shorter than its tag says stops at the same point every time. Without a limit, an album would
/// stall on that track for ever, with no message. That is worse than skipping the track.
@Suite("How many goes a track gets")
struct RetriesTests {
    @Test func aTrackGetsThreeGoesAndThenTheQueueMovesOn() {
        var retries = Retries()
        let goes = (0..<5).map { _ in retries.mayRetry("a") }

        #expect(goes == [true, true, true, false, false])
    }

    /// **Counted per track, not per session.** Many stumbles on one album must not use up a
    /// shared budget.
    @Test func adifferentTrackStartsAgainFromThree() {
        var retries = Retries()

        _ = retries.mayRetry("a")
        _ = retries.mayRetry("a")
        _ = retries.mayRetry("a")

        let again = retries.mayRetry("a")
        let other = retries.mayRetry("b")

        #expect(!again)
        #expect(other)
        #expect(retries.used("b") == 1)
    }

    /// A track that played successfully has its attempts reset. A stumble later in the session
    /// gets the full three again.
    @Test func aTrackThatPlayedHasItsTroublesBehindIt() {
        var retries = Retries()

        _ = retries.mayRetry("a")
        _ = retries.mayRetry("a")
        retries.forget()

        #expect(retries.used("a") == 0)

        let goes = (0..<3).map { _ in retries.mayRetry("a") }
        #expect(goes == [true, true, true])
    }

    /// A track with an empty id is not a real track. Retrying it would retry whatever track next
    /// has an empty id.
    @Test func somethingWithNoNameGetsNoGoes() {
        var retries = Retries()
        let given = retries.mayRetry("")

        #expect(!given)
    }

    @Test func aGoIsCountedTheMomentItIsGiven() {
        var retries = Retries()

        #expect(retries.used("a") == 0)
        _ = retries.mayRetry("a")
        #expect(retries.used("a") == 1)
        #expect(retries.used("b") == 0)
    }
}
