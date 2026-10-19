import Testing
@testable import RPMAudio

/// Whether a play counts as a listen.
///
/// The rule must match the desktop app. Counts from the phone and the desktop are added together,
/// so a different rule on either side would change every total. The desktop rule is in
/// `RPM.Core/Playback/Listen.cs`.
struct ListenTests {
    @Test func aFlickPastIsNotAPlay() {
        #expect(Listen.counts(heard: 3, length: 240) == false)
    }

    @Test func halfARecordIsAPlay() {
        #expect(Listen.counts(heard: 120, length: 240))
    }

    @Test func fourMinutesOfALongSideIsAPlay() {
        #expect(Listen.counts(heard: 240, length: 1200))
    }

    @Test func aTrackTooShortToJudgeNeverCounts() {
        #expect(Listen.counts(heard: 20, length: 20) == false)
    }

    /// A length of zero means the catalogue has no length for the row. A phone often sees such rows
    /// first. Guessing a length would count a quick skip as a play.
    @Test func aTrackOfUnknownLengthNeverCounts() {
        #expect(Listen.counts(heard: 300, length: 0) == false)
    }

    @Test func aRecordThatPlayedSilentlyCountsNothing() {
        #expect(Listen.counts(heard: 0, length: 240) == false)
    }

    @Test func aFlickPastIsNotEvenWorthRecording() {
        #expect(Listen.worthRecording(heard: 2, length: 240) == false)
    }

    /// Wider than `counts` on purpose. A skip that is not a play is still recorded, so the app can
    /// tell that a track keeps being skipped.
    @Test func aSkipIsWorthRecordingEvenThoughItIsNotAPlay() {
        #expect(Listen.worthRecording(heard: 30, length: 240))
        #expect(Listen.counts(heard: 30, length: 240) == false)
    }
}

/// How much of a track the listener heard, added up across seeks.
///
/// The engine's counter cannot give this total. A seek starts a new decoder, and the counter goes
/// back to zero. A reader that takes the highest value seen would get only the longest unbroken
/// stretch, not the total listening. The desktop version is `RPM.Core/Playback/ListenTally.cs`.
struct ListenTallyTests {
    @Test func aStretchIsWhatWasHeard() {
        var tally = ListenTally()

        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 120, lengthSeconds: 300)

        #expect(tally.heardSeconds == 120)
    }

    /// A seek starts a new play session part way into the track. The stretch so far is saved, and
    /// the counter starts again from zero.
    @Test func twoStretchesEitherSideOfASeekAddUp() {
        var tally = ListenTally()

        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 120, lengthSeconds: 300)
        _ = tally.read(track: "a", session: 2, startSeconds: 60, heardSeconds: 0, lengthSeconds: 300)
        _ = tally.read(track: "a", session: 2, startSeconds: 60, heardSeconds: 60, lengthSeconds: 300)

        #expect(tally.heardSeconds == 180)
    }

    /// A restart is a new session at the very top of the track. It is a second listen, not a seek.
    @Test func aRestartSettlesTheListenBeforeIt() {
        var tally = ListenTally()
        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 290, lengthSeconds: 300)

        let settled = tally.read(track: "a", session: 2, startSeconds: 0,
                                 heardSeconds: 0, lengthSeconds: 300)

        #expect(settled?.track == "a")
        #expect(settled?.heardSeconds == 290)
        #expect(tally.heardSeconds == 0)
    }

    @Test func aTrackChangeSettlesTheOneBefore() {
        var tally = ListenTally()
        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 200, lengthSeconds: 300)

        let settled = tally.read(track: "b", session: 1, startSeconds: 0,
                                 heardSeconds: 0, lengthSeconds: 300)

        #expect(settled?.track == "a")
        #expect(settled?.heardSeconds == 200)
    }

    /// A reading taken early, while the sink still plays the end of the outgoing track, must not
    /// lower the total. The total never goes down.
    @Test func aStretchNeverGoesDownwards() {
        var tally = ListenTally()

        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 120, lengthSeconds: 300)
        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 3, lengthSeconds: 300)

        #expect(tally.heardSeconds == 120)
    }

    @Test func settlingTwiceCountsOnce() {
        var tally = ListenTally()
        _ = tally.read(track: "a", session: 1, startSeconds: 0, heardSeconds: 200, lengthSeconds: 300)

        #expect(tally.settle()?.track == "a")
        #expect(tally.settle() == nil)
    }

    @Test func nothingPlayingSettlesNothing() {
        var tally = ListenTally()

        #expect(tally.read(track: nil, session: 0, startSeconds: 0,
                           heardSeconds: 0, lengthSeconds: 0) == nil)
        #expect(tally.settle() == nil)
    }
}
