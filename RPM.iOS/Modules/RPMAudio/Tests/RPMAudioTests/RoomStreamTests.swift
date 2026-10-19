import Foundation
import Testing
import RPMCast
@testable import RPMAudio

/// What the speaker (the room) is holding from this app, and what its status messages mean given that.
///
/// **The fault these tests cover.** Pressing play starts playback on the speaker for half a second.
/// Then the speaker stops, and the queue on the remote control is emptied.
///
/// A track change removes our stream from the receiver before the next stream is sent. For about
/// half a second in between, the receiver reports the same as when someone presses stop on it: it
/// holds nothing. The player read that as a press on the speaker and stopped the music. The
/// reading is kept as a value with no network code, so these cases can be tested without a speaker.
@Suite("What the room is holding")
struct RoomStreamTests {

    private func said(_ session: Int, _ state: String, reason: String? = nil,
                      at seconds: Double = 10) -> RoomReport {
        var payload = #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":\#(session),"#
        payload += #""playerState":"\#(state)","currentTime":\#(seconds)"#
        if let reason { payload += #","idleReason":"\#(reason)""# }
        payload += "}]}"

        guard let status = MediaStatus.of(payload) else { return .noAnswer }
        return .holding(status)
    }

    private func device(_ payload: String) throws -> ReceiverStatus {
        struct Envelope: Decodable { let status: ReceiverStatus }
        return try JSONDecoder().decode(Envelope.self, from: Data(payload.utf8)).status
    }

    /// The player state while a track is playing. It is built with the `Playback` methods, not by
    /// setting fields.
    private var playing: Playback {
        var it = Playback(); it.aRecordWentOn(.somebodyAskedForIt); it.movedToTheRoom(); return it
    }

    /// The player state after the user pauses.
    private var paused: Playback {
        var it = playing; it.somebodyPressedPause(); return it
    }

    private func casting(session: Int = 7) -> RoomStream {
        var room = RoomStream()
        room.nowHolding(session)
        return room
    }

    // During a track change.

    /// **The reported fault.** The stream is removed and the next one is not sent yet. The
    /// receiver holds nothing and says so. This is not a stop.
    @Test func aRoomEmptiedByATrackChangeIsNotAStop() {
        var room = casting()
        room.takenBack()

        #expect(room.reading(.nothingLoaded, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// The receiver can also report a cut stream as IDLE with reason CANCELLED. That is the same
    /// reason it uses for a stop, so during a change this is not a stop either.
    @Test func aCancelledStreamMidChangeoverIsNotAStop() {
        var room = casting()
        room.takenBack()

        #expect(room.reading(said(7, "IDLE", reason: "CANCELLED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// Once the new stream is loaded, the room's answers count again.
    @Test func aRoomHoldingTheNewStreamIsNewsAgain() {
        var room = casting()
        room.takenBack()
        room.nowHolding(9)

        #expect(room.reading(.nothingLoaded, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .stopped(.holdingNothing))
    }

    /// A status about the replaced stream carries its old session id. The check uses that id, so
    /// it does not depend on how long a changeover takes.
    @Test func aStatusAboutTheOldStreamIsIgnored() {
        var room = casting(session: 7)
        room.takenBack()
        room.nowHolding(9)

        #expect(room.reading(said(7, "IDLE", reason: "CANCELLED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// **A race that the session id alone cannot catch.** The poll asks, the track changes, the
    /// LOAD lands, and then the answer to the old question arrives. It says the room holds nothing.
    /// That was true when it was asked, but it is not true now. A "nothing loaded" answer has no
    /// session id, so the question carries a stamp (`turns`) instead.
    @Test func anAnswerToAQuestionAskedBeforeTheChangeoverIsDropped() {
        var room = casting()
        let asked = room.turns

        room.takenBack()
        room.nowHolding(9)

        #expect(room.reading(.nothingLoaded, askedUnder: asked,
                             toldUnder: room.stamp, against: playing) == .nothing)
        #expect(room.reading(.nothingLoaded, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .stopped(.holdingNothing))
    }

    // A hand on the speaker (a press on the speaker itself).

    /// The receiver keeps its app running but clears its media. This is a stop.
    @Test func anEmptyRoomIsAStop() {
        var room = casting()

        #expect(room.reading(.nothingLoaded, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .stopped(.holdingNothing))
    }

    /// IDLE with a reason other than a finished track is a stop.
    @Test func idleCancelledAndInterruptedAreStops() {
        var room = casting()

        #expect(room.reading(said(7, "IDLE", reason: "CANCELLED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .stopped(.letTheMusicGo))
        #expect(room.reading(said(7, "IDLE", reason: "INTERRUPTED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .stopped(.letTheMusicGo))
    }

    /// **This must not be a stop.** When our stream runs out, the track has ended and the queue
    /// moves on. Treating it as a stop would stop the queue.
    @Test func idleFinishedIsNotAStop() {
        var room = casting()

        #expect(room.reading(said(7, "IDLE", reason: "FINISHED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// A URL the receiver cannot fetch also arrives as IDLE, with reason ERROR. This is not a
    /// request for silence either.
    @Test func idleErrorIsNotAStop() {
        var room = casting()

        #expect(room.reading(said(7, "IDLE", reason: "ERROR"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    // Pause and resume from the room.

    /// A pause from the speaker's own controls, or from the Home app ("Hey Google, pause").
    /// **Some speakers only send this, and nothing else,** so it is the only signal the phone gets.
    @Test func aPausedRoomPausesThePlayer() {
        var room = casting()

        #expect(room.reading(said(7, "PAUSED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .pause)
    }

    /// **Our own pause is not read as a press.** The engine pauses first, and the receiver reports
    /// the pause back later.
    @Test func aPausedRoomUnderOurOwnPauseIsNotNews() {
        var room = casting()

        #expect(room.reading(said(7, "PAUSED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: paused) == .nothing)
    }

    @Test func aRoomPlayingUnderOurPauseResumesThePlayer() {
        var room = casting()

        #expect(room.reading(said(7, "PLAYING"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: paused) == .resume)
        #expect(room.reading(said(7, "PLAYING"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// A receiver that keeps playing is not an event.
    @Test func aRoomPlayingIsNotNews() {
        var room = casting()

        #expect(room.reading(said(7, "PLAYING", at: 42), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
        #expect(room.reading(said(7, "BUFFERING"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    // The speaker did not answer.

    /// A timed-out request is not a stop. Reading it as one would stop the music each time the
    /// home network had a short fault.
    @Test func silenceIsNotAStop() {
        var room = casting()

        #expect(room.reading(.noAnswer, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// Before anything is loaded, nothing from this app is in the room. So nothing it says is
    /// about this app.
    @Test func aRoomHoldingNothingOfOursIsNeverNews() {
        var room = RoomStream()

        #expect(room.reading(.nothingLoaded, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
        #expect(room.reading(said(7, "IDLE", reason: "CANCELLED"), askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    // The device's own status.

    private let running = """
        {"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"41BD77B1",
        "sessionId":"s-1","transportId":"t-1","displayName":"rpm"}],
        "volume":{"level":0.4}}}
        """

    private let idle = #"{"type":"RECEIVER_STATUS","status":{"volume":{"level":0.4}}}"#

    /// A stop on a Google speaker quits the receiver app, and the media session ends with it.
    @Test func aClosedReceiverIsAStop() throws {
        var room = casting()

        #expect(try room.reading(device(running), ours: "s-1",
                                 askedUnder: room.turns) == .nothing)
        #expect(try room.reading(device(idle), ours: "s-1",
                                 askedUnder: room.turns) == .stopped(.closedTheReceiver))
    }

    /// A receiver that is running a different session is not this cast either.
    @Test func someoneElsesSessionIsAStop() throws {
        var room = casting()

        #expect(try room.reading(device(running), ours: "s-2",
                                 askedUnder: room.turns) == .stopped(.closedTheReceiver))
    }

    /// **The device question needs the same stamp as the transport question.** Without it, the
    /// answer to a question asked before a skip can arrive after the skip. The window is about a
    /// quarter of a second.
    @Test func aDeviceAnswerAboutTheWorldBeforeASkipIsDropped() throws {
        var room = casting()
        let asked = room.turns

        room.takenBack()
        room.nowHolding(9)

        #expect(try room.reading(device(idle), ours: "s-1", askedUnder: asked) == .nothing)
        #expect(try room.reading(device(idle), ours: "s-1",
                                 askedUnder: room.turns) == .stopped(.closedTheReceiver))
    }

    /// **A Google speaker quits its receiver app when it is idle. It does not stay on an idle
    /// receiver.** A changeover causes the same state. During a skip, the device correctly reports
    /// that our session is gone. That comes from our own change, not from a press on the speaker.
    @Test func aReceiverClosedByOurOwnChangeoverIsNotAStop() throws {
        var room = casting()
        room.takenBack()

        #expect(try room.reading(device(idle), ours: "s-1",
                                 askedUnder: room.turns) == .nothing)
    }

    // The stamp and the session.

    /// Removing the stream and forgetting the session both move the stamp. A question asked before
    /// either change is about a different state of the room.
    @Test func everyChangeMovesTheStamp() {
        var room = RoomStream()
        #expect(room.session == nil)

        room.nowHolding(7)
        #expect(room.session == 7)
        #expect(room.turns == 1)

        room.takenBack()
        #expect(room.session == nil)
        #expect(room.turns == 2)

        room.nowHolding(9)
        #expect(room.session == 9)
        #expect(room.turns == 3)

        room.gone()
        #expect(room.session == nil)
        #expect(room.turns == 4)
    }

    // A key pressed on this device.

    /// **A pause that needed two presses.** The engine pauses at once, but the room only pauses
    /// after a network round trip. A poll in between reports that the room is still playing. Read
    /// as it is, that looks like a press of play on the speaker. The reply would be to play again,
    /// which undoes the pause. The next pause press then only works after the room catches up.
    @Test func aRoomStillPlayingBecauseItHasNotBeenToldYetIsNotAHandOnTheSpeaker() {
        var room = casting()
        let asked = room.turns
        let told = room.stamp

        // Pause pressed here. The engine is paused, but the room is not yet.
        room.toldIt()

        #expect(room.reading(said(7, "PLAYING"), askedUnder: asked, toldUnder: told,
                             against: paused) == .nothing)
    }

    /// Once the room has been told, a disagreement is real news. It is a press on the speaker, and
    /// it must still be handled.
    @Test func aRoomStillPlayingAfterItWasToldIsAHandOnTheSpeaker() {
        var room = casting()
        room.toldIt()
        room.heardBack()

        #expect(room.reading(said(7, "PLAYING"), askedUnder: room.turns, toldUnder: room.stamp,
                             against: paused) == .resume)
    }

    /// The same race in the other direction. The `soundIsPaused` guard covers it. Our own pause,
    /// reported back to us, is not a press on anything.
    @Test func aRoomReportingOurOwnPauseBackToUsIsNotNews() {
        var room = casting()
        room.toldIt()
        room.heardBack()

        #expect(room.reading(said(7, "PAUSED"), askedUnder: room.turns, toldUnder: room.stamp,
                             against: paused) == .nothing)
    }

    /// **Play that paused itself.** Play is pressed on the lock screen. The key is stamped and sent
    /// from a task, while the poll runs on its own loop. The poll can ask under the new time and
    /// get its GET_STATUS onto the socket first. The receiver answers in order, so it reports
    /// PAUSED before it has processed PLAY. That was read as a press of pause on the speaker. The
    /// player then paused itself about 160 ms after the key, and the next pause press had nothing
    /// to pause.
    @Test func aQuestionAskedWhileAKeyIsOnItsWayIsNotAHandOnTheSpeaker() {
        var room = casting()

        // Play pressed. The key is sent but not yet answered.
        room.toldIt()

        // The poll asks now. The room answers from before it saw the key.
        let told = room.stamp
        #expect(room.reading(said(7, "PAUSED"), askedUnder: room.turns, toldUnder: told,
                             against: playing) == .nothing)
    }

    /// Once the key has been answered, a disagreement is a press on the speaker again. The fix must
    /// not stop the speaker's own pause key from working.
    @Test func aPauseAtTheSpeakerAfterOurPlayWasAnsweredIsStillAHand() {
        var room = casting()
        room.toldIt()
        room.heardBack()

        #expect(room.reading(said(7, "PAUSED"), askedUnder: room.turns, toldUnder: room.stamp,
                             against: playing) == .pause)
    }

    // How far the sitting has got.

    /// The sitting must be on as soon as a speaker is picked up. `theRoomSaid` returns early when
    /// there is no cast, so an answer that arrives during setup would be dropped, including the
    /// first status after a LOAD.
    @Test func theSittingIsOnFromTheMomentASpeakerIsPickedUp() {
        var room = RoomStream()
        #expect(room.isOn == false)

        room.pickingUp()
        #expect(room.isOn, "the sitting begins when the speaker is picked up")
        #expect(room.session == nil, "and it is holding nothing of ours yet")
    }

    /// While connecting, the stage cannot hear the room. The room holds nothing from this app yet,
    /// so its empty state is expected and not a stop.
    @Test func aRoomHoldingNothingOfOursIsNotNewsWhileConnecting() {
        var room = RoomStream()
        room.pickingUp()

        #expect(room.reading(.nothingLoaded, askedUnder: room.turns,
                             toldUnder: room.stamp, against: playing) == .nothing)
    }

    /// The stages in order. The session is carried through the two stages that have one.
    @Test func theSittingGoesConnectingThenHoldingThenPlaying() {
        var room = RoomStream()

        room.pickingUp()
        #expect(room.stage == .connecting)

        room.nowHolding(7)
        #expect(room.stage == .holding(session: 7))
        #expect(room.session == 7)

        room.itFetched()
        #expect(room.stage == .playing(session: 7), "the fetch watchdog's stage is over")
        #expect(room.session == 7, "and the session it carries does not change")

        room.gone()
        #expect(room.stage == .gone)
        #expect(room.isOn == false)
        #expect(room.session == nil)
    }

    /// A fetch reported before any LOAD was sent is not a fetch from this app.
    @Test func aFetchBeforeALoadIsNotAFetch() {
        var room = RoomStream()
        room.pickingUp()

        room.itFetched()

        #expect(room.stage == .connecting, "there was no stream for it to have fetched")
    }

    /// A track change removes the stream and then sends the next one. The sitting stays on across
    /// the change. `takenBack` handles this part.
    @Test func aTrackChangeKeepsTheSittingButNotTheSession() {
        var room = RoomStream()
        room.pickingUp()
        room.nowHolding(7)
        room.itFetched()

        room.takenBack()

        #expect(room.isOn, "the speaker is still there")
        #expect(room.session == nil, "it is holding nothing of ours for the moment")
    }

    // A key with no session to send it to.

    /// **A key pressed during a changeover is kept, not dropped.** Every transport message needs a
    /// media session. During a changeover there is none: `takenBack` clears it when our stream
    /// leaves the receiver, and `nowHolding` sets it again only after the next LOAD is
    /// acknowledged. `Player.tellTheRoom` needs a session to send a key. Without one, the key must
    /// be kept and sent later. Otherwise a pause press would be lost and the speaker would keep
    /// playing.
    @Test func aKeyPressedWithNoSessionIsOwedRatherThanDropped() {
        var room = casting()
        room.takenBack()
        #expect(room.session == nil, "mid-changeover: nothing to send a key under")

        room.owe(playing: false)

        room.nowHolding(9)
        #expect(room.settleUp() == false, "the pause was still owed when the room could hear it")
        #expect(room.settleUp() == nil, "and paying it twice would pause the next record")
    }

    /// The last key wins. A pause followed by a play in the same window means the listener wants
    /// play.
    @Test func theLastKeyPressedInTheWindowIsTheOneThatIsOwed() {
        var room = casting()
        room.takenBack()

        room.owe(playing: false)
        room.owe(playing: true)

        #expect(room.settleUp() == true)
    }

    /// If no key was pressed, nothing is sent. A changeover with no key pressed must not send a
    /// key of its own.
    @Test func aQuietChangeoverOwesNothing() {
        var room = casting()
        room.takenBack()
        room.nowHolding(9)

        #expect(room.settleUp() == nil)
    }

    /// A sitting that has ended owes nothing to the next speaker.
    @Test func aSittingThatEndedCarriesNoDebtIntoTheNext() {
        var room = casting()
        room.takenBack()
        room.owe(playing: false)

        room.gone()

        #expect(room.settleUp() == nil, "the next speaker would have been paused on connecting")
    }
}
