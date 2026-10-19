import Testing
import Foundation
@testable import RPMAudio
import RPMKit

/// The counter between the player and the play log.
///
/// A play is counted once, at the same point as on the desktop. A track with no cloud id is never
/// counted. The counter returns the play rather than writing it. The readings must arrive in the
/// order the player took them. If the tally gets them out of order, it scores the wrong stretch.
@MainActor
struct PlayCounterTests {
    /// CloudTrackTags has no public memberwise init, so it is built and then filled.
    private func tags(_ seconds: Double) -> CloudTrackTags {
        var made = CloudTrackTags()
        made.durationSeconds = seconds
        return made
    }

    private func track(_ id: String, seconds: Double = 300) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "a/\(id).flac", title: id, tags: tags(seconds))
    }

    @Test func aRecordHeardThroughCountsOnce() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        #expect(counter.read(track: track("t1"), session: 1, position: 200, duration: 300) == nil)
        let counted = counter.read(track: track("t2"), session: 1, position: 0, duration: 300)

        #expect(counted?.rpmId == "t1")
    }

    @Test func aFlickPastCountsNothing() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 3, duration: 300)
        let counted = counter.read(track: track("t2"), session: 1, position: 0, duration: 300)

        #expect(counted == nil)
    }

    @Test func aTrackWithNoCloudIdCountsNowhere() {
        let counter = PlayCounter()
        let local = CloudTrack(rpmId: "", relativePath: "a/x.flac", tags: tags(300))

        _ = counter.read(track: local, session: 1, position: 0, duration: 300)
        _ = counter.read(track: local, session: 1, position: 200, duration: 300)
        let counted = counter.read(track: track("t2"), session: 1, position: 0, duration: 300)

        #expect(counted == nil)
    }

    /// A restart is a new session at the top of the track, which is a second listen rather than a
    /// seek back. A record on repeat has to count every pass.
    @Test func aRecordOnRepeatCountsEveryPass() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 290, duration: 300)
        let first = counter.read(track: track("t1"), session: 2, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 2, position: 290, duration: 300)
        let second = counter.settle()

        #expect(first?.rpmId == "t1")
        #expect(second?.rpmId == "t1")
    }

    /// A seek forward must not credit the part nobody heard: what counts is audio delivered, and
    /// the seek starts a new stretch at the position it landed on.
    @Test func skippingToTheEndDoesNotCountAsHavingHeardIt() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 5, duration: 300)
        // The needle is dragged to 4:50. A new session, not at the top, so the same listen carries
        // on with its counter back at zero.
        _ = counter.read(track: track("t1"), session: 2, position: 290, duration: 300)
        _ = counter.read(track: track("t1"), session: 2, position: 295, duration: 300)

        #expect(counter.settle() == nil)
    }

    /// The other half of the same rule: two real stretches either side of a seek add up to a play.
    @Test func twoStretchesEitherSideOfASeekAddUpToAPlay() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 100, duration: 300)
        _ = counter.read(track: track("t1"), session: 2, position: 20, duration: 300)
        _ = counter.read(track: track("t1"), session: 2, position: 80, duration: 300)

        #expect(counter.settle()?.rpmId == "t1")
    }

    @Test func goingAwayWithARecordOnSettlesIt() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 200, duration: 300)

        #expect(counter.settle()?.rpmId == "t1")
        #expect(counter.settle() == nil)
    }

    @Test func theStampIsWhenTheListenEnded() {
        let counter = PlayCounter(now: { Date(timeIntervalSince1970: 4242) })

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 200, duration: 300)

        #expect(counter.settle()?.at == 4242)
    }

    /// Picking up where it stopped starts the stretch at the needle: the listener has not heard
    /// the part before it in this session, and crediting it would count a play for putting a
    /// record back on near its end.
    @Test func resumingPartwayThroughCreditsOnlyWhatIsHeardFromThere() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 280, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 300, duration: 300)

        #expect(counter.settle() == nil)
    }

    /// Leaving and returning in the middle of a track counts one listen, not two.
    ///
    /// Settling empties the tally, but the audio keeps playing. The next reading starts a new listen
    /// at the current position. It must not credit the time that the settle already counted.
    /// Otherwise each trip to the home screen would add another play.
    @Test func backgroundingMidTrackDoesNotCountTheSameListenTwice() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1", seconds: 240), session: 1, position: 0, duration: 240)
        _ = counter.read(track: track("t1", seconds: 240), session: 1, position: 150, duration: 240)
        #expect(counter.settle()?.rpmId == "t1")

        // Back in the app, same session. The record plays on to its end.
        _ = counter.read(track: track("t1", seconds: 240), session: 1, position: 152, duration: 240)
        _ = counter.read(track: track("t1", seconds: 240), session: 1, position: 240, duration: 240)

        // Eighty-eight seconds of a four-minute track, which is not a play.
        #expect(counter.settle() == nil)
    }

    /// A seek passes in the position where it landed. The position is not read from the player.
    /// While casting, the needle moves some seconds before the engine follows it. If the position
    /// were read from the player, a jump from the start to the last minute would count the whole
    /// jump as listening.
    @Test func aSeekToldWhereItLandedCreditsNothingItSkipped() {
        let counter = PlayCounter()

        _ = counter.read(track: track("t1"), session: 1, position: 0, duration: 300)
        _ = counter.read(track: track("t1"), session: 1, position: 10, duration: 300)

        counter.seeked(to: 200)
        // The timer still reads the old position for a moment, because the room has not received
        // the new stream yet.
        _ = counter.read(track: track("t1"), session: 2, position: 10, duration: 300)
        _ = counter.read(track: track("t1"), session: 2, position: 205, duration: 300)

        // Ten seconds heard, then five. Not a play, and certainly not the 195 that were skipped.
        #expect(counter.settle() == nil)
    }

        /// The radio has no track and no length, so there is nothing to count or settle.
    @Test func theRadioCountsNothing() {
        let counter = PlayCounter()

        _ = counter.read(track: nil, session: 1, position: 600, duration: 0)

        #expect(counter.settle() == nil)
    }
}
