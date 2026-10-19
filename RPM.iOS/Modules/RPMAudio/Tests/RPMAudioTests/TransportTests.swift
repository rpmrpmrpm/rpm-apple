import Testing
@testable import RPMAudio

/// Play and pause pressed while a track is still opening. During this time the engine holds
/// nothing, so the honest answer to "is it playing?" is no. If this goes wrong, nothing throws.
/// The press is dropped, and a track that should have stayed silent starts playing a second later.
///
/// Each case matches a test in `RPM.Core.Tests/TransportTests.cs`, so the two code bases
/// behave the same.
@Suite("Play and pause while a track is opening")
struct TransportTests {

    // The window while a track opens.

    @Test func pausePressedWhileATrackIsOpeningIsRememberedNotDropped() {
        var transport = Transport()
        transport.starting()

        let move = transport.pause(starting: true, loaded: .nothing)
        #expect(move == .remember)
        #expect(transport.pausePending)
    }

    @Test func aRememberedPauseIsAppliedWhenTheSourceArrives() {
        var transport = Transport()
        transport.starting()
        _ = transport.pause(starting: true, loaded: .nothing)

        let arrived1 = transport.arrives()
        #expect(arrived1)
    }

    @Test func aRememberedPauseIsAppliedOnceAndNotToTheTrackAfterIt() {
        var transport = Transport()
        transport.starting()
        _ = transport.pause(starting: true, loaded: .nothing)

        let arrived2 = transport.arrives()
        #expect(arrived2)
        let arrived3 = transport.arrives()
        #expect(!arrived3)
    }

    @Test func playPressedWhileATrackIsOpeningWithdrawsARememberedPause() {
        var transport = Transport()
        transport.starting()
        _ = transport.pause(starting: true, loaded: .nothing)

        let move = transport.play(starting: true, loaded: .nothing)
        #expect(move == .forget)
        let arrived4 = transport.arrives()
        #expect(!arrived4)
    }

    /// The lock screen sends play and pause as separate commands. This case checks that play
    /// pressed during a load does not turn into a pause.
    @Test func playPressedWhileATrackIsOpeningNeverPausesIt() {
        var transport = Transport()
        transport.starting()

        let move = transport.play(starting: true, loaded: .nothing)
        #expect(move == .nothing)
        #expect(!transport.pausePending)
        let arrived5 = transport.arrives()
        #expect(!arrived5)
    }

    @Test func pausePressedTwiceWhileOpeningStaysPaused() {
        var transport = Transport()
        transport.starting()

        let move = transport.pause(starting: true, loaded: .nothing)
        #expect(move == .remember)
        let move2 = transport.pause(starting: true, loaded: .nothing)
        #expect(move2 == .nothing)
        let arrived6 = transport.arrives()
        #expect(arrived6)
    }

    @Test func choosingAnotherTrackForgetsAPausePressedAgainstTheLastOne() {
        var transport = Transport()
        transport.starting()
        _ = transport.pause(starting: true, loaded: .nothing)

        transport.starting()   // Next was pressed, so this track is the one the listener asked for.

        #expect(!transport.pausePending)
        let arrived7 = transport.arrives()
        #expect(!arrived7)
    }

    @Test func stoppingForgetsARememberedPause() {
        var transport = Transport()
        transport.starting()
        _ = transport.pause(starting: true, loaded: .nothing)

        transport.forgotten()

        let arrived8 = transport.arrives()
        #expect(!arrived8)
    }

    @Test func aPauseWithNothingPlayingAndNothingComingIsNotHeldAgainstTheNextTrack() {
        var transport = Transport()

        let move = transport.pause(starting: false, loaded: .nothing)
        #expect(move == .nothing)
        #expect(!transport.pausePending)
    }

    // The ordinary cases, which must keep working.

    @Test func pauseOnAPlayingTrackPausesIt() {
        var transport = Transport()
        let move = transport.pause(starting: false, loaded: .playing)
        #expect(move == .pause)
    }

    @Test func playOnAPausedTrackResumesIt() {
        var transport = Transport()
        let move = transport.play(starting: false, loaded: .paused)
        #expect(move == .resume)
    }

    @Test func playOnAPlayingTrackDoesNothing() {
        var transport = Transport()
        let move = transport.play(starting: false, loaded: .playing)
        #expect(move == .nothing)
    }

    @Test func pauseOnAPausedTrackDoesNothing() {
        var transport = Transport()
        let move = transport.pause(starting: false, loaded: .paused)
        #expect(move == .nothing)
    }

    @Test func theEngineWinsOverAStaleStartFlag() {
        var transport = Transport()
        transport.starting()

        // The source has been handed over, but the load has not finished its cleanup. The
        // engine's state is the answer.
        let move = transport.pause(starting: true, loaded: .playing)
        #expect(move == .pause)
        #expect(transport.wantsToPlay(starting: true, loaded: .playing))
    }

    // What the play/pause key shows.

    @Test func anOpeningTrackShowsAPauseKeyBecauseThatIsWhatWasAskedFor() {
        var transport = Transport()
        transport.starting()

        #expect(transport.wantsToPlay(starting: true, loaded: .nothing))
    }

    @Test func anOpeningTrackShowsAPlayKeyOncePauseHasBeenPressed() {
        var transport = Transport()
        transport.starting()
        _ = transport.pause(starting: true, loaded: .nothing)

        #expect(!transport.wantsToPlay(starting: true, loaded: .nothing))
    }

    @Test func anIdlePlayerShowsAPlayKey() {
        #expect(!Transport().wantsToPlay(starting: false, loaded: .nothing))
    }

    // The toggle.

    @Test func theTogglePausesATrackThatIsPlaying() {
        var transport = Transport()
        let move = transport.toggle(starting: false, loaded: .playing)
        #expect(move == .pause)
    }

    @Test func theToggleResumesATrackThatIsPaused() {
        var transport = Transport()
        let move = transport.toggle(starting: false, loaded: .paused)
        #expect(move == .resume)
    }

    @Test func theToggleRemembersAPauseWhileATrackIsOpening() {
        var transport = Transport()
        transport.starting()

        let move = transport.toggle(starting: true, loaded: .nothing)
        #expect(move == .remember)
    }

    @Test func theToggleTakesARememberedPauseBack() {
        var transport = Transport()
        transport.starting()
        _ = transport.toggle(starting: true, loaded: .nothing)

        let move = transport.toggle(starting: true, loaded: .nothing)
        #expect(move == .forget)
        let arrived9 = transport.arrives()
        #expect(!arrived9)
    }

    @Test func theToggleDoesNothingWhenThereIsNothingLoadedAndNothingComing() {
        var transport = Transport()
        let move = transport.toggle(starting: false, loaded: .nothing)
        #expect(move == .nothing)
    }
}
