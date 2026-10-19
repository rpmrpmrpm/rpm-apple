import Testing
@testable import RPMAudio

/// **The rule this type enforces, checked for every way the state can change.**
///
/// Only a person's action may change what is playing or paused. The table below walks every way
/// `Playback` can change, and checks whether that change was allowed to move `doing`. A new way
/// to change the state must be added to the table. `everyDoorIsAccountedFor` fails if one is
/// missing.
@Suite("What may change what is playing")
struct PlaybackTests {

    /// Every door, and whether a person came through it.
    ///
    /// Each entry holds a name for the door and a closure that opens it. The list is data, not one
    /// test per door, so the two tests below check *all* of them. A door that nobody thought about
    /// is still in this list.
    private static func doors() -> [(String, somebodyAsked: Bool, open: (inout Playback) -> Void)] { [
        ("somebodyPressedPlay",       true,  { $0.somebodyPressedPlay() }),
        ("somebodyPressedPause",      true,  { $0.somebodyPressedPause() }),
        ("aRecordWentOn(asked)",      true,  { $0.aRecordWentOn(.somebodyAskedForIt) }),
        ("aRecordWentOn(carryOn)",    false, { $0.aRecordWentOn(.carryOnAsBefore) }),
        ("theRoomSaid(playing:)",     true,  { $0.theRoomSaid(playing: true) }),
        ("nothingIsLeft",             true,  { $0.nothingIsLeft() }),

        ("theQueueMovedOn",           false, { $0.theQueueMovedOn() }),
        ("theRecordWasMovedThrough",  false, { $0.theRecordWasMovedThrough() }),
        ("movedToTheRoom",            false, { $0.movedToTheRoom() }),
        ("cameHome",                  false, { $0.cameHome() }),
    ] }

    /// Every state a player can be sitting in when a door opens.
    private static func everyState() -> [Playback] {
        var out: [Playback] = []
        for casting in [false, true] {
            for build in [{ (p: inout Playback) in },
                          { $0.aRecordWentOn(.somebodyAskedForIt) },
                          { $0.aRecordWentOn(.somebodyAskedForIt); $0.somebodyPressedPause() }] {
                var p = Playback()
                if casting { p.movedToTheRoom() }
                build(&p)
                out.append(p)
            }
        }
        return out
    }

    /// **The rule.** A door that the machinery opens may change the destination and the source.
    /// It may not change a record that is playing or paused into a different state.
    ///
    /// Starting a record where nothing was playing is allowed. Nobody has asked for silence, so
    /// there is nothing to keep. Every other change needs a person's action.
    @Test func nothingButAskingMovesARecordThatIsPlayingOrPaused() {
        for (name, somebodyAsked, open) in Self.doors() where !somebodyAsked {
            for before in Self.everyState() where before.doing != .nothing {
                var after = before
                open(&after)

                #expect(after.doing == before.doing,
                        "\(name) moved doing from \(before.doing) to \(after.doing)")
            }
        }
    }

    /// The other half of the rule. A type that never changes would pass the test above, so this
    /// test checks that a person's action does change the state.
    @Test func aPersonAtTheDoorIsAnswered() {
        var playing = Playback()
        playing.aRecordWentOn(.somebodyAskedForIt)
        #expect(playing.doing == .playing)

        var paused = playing
        paused.somebodyPressedPause()
        #expect(paused.doing == .paused)

        var again = paused
        again.somebodyPressedPlay()
        #expect(again.doing == .playing)

        var picked = paused
        picked.aRecordWentOn(.somebodyAskedForIt)
        #expect(picked.doing == .playing, "asking to hear something is asking for it to play")
    }

    /// A door with no line in the table is a door that is not tested.
    ///
    /// The count is of **doors**, not table lines. `aRecordWentOn` has one line per `Start` case,
    /// because its result depends on the case. Nine is the number of `public mutating func`s on
    /// `Playback`. This count is the only check that keeps the table in step with the type,
    /// because Swift cannot list the functions of a type.
    @Test func everyDoorIsAccountedFor() {
        let named = Set(Self.doors().map { $0.0.prefix { $0 != "(" } })

        #expect(named.count == 9, """
            A door was added to `Playback` without a line in `doors`. Add it, and say \
            whether a person came through it. Doors covered: \(named.sorted())
            """)
    }

    // ── known bad cases, each as the state that caused it ──

    /// The pump's pause check was `paused && toTheRoom != nil`. Bringing the sound home cleared
    /// that check, so the record started playing on the handset by itself.
    @Test func comingHomeDoesNotStartAPausedRecord() {
        var it = Playback()
        it.aRecordWentOn(.somebodyAskedForIt)
        it.movedToTheRoom()
        it.somebodyPressedPause()

        it.cameHome()

        #expect(it.isPaused)
        #expect(it.isCasting == false)
    }

    /// `begin` cleared the pause on every source it started. So when a record ended while paused,
    /// the next one started playing.
    @Test func theQueueMovingOnDoesNotStartAPausedRecord() {
        var it = Playback()
        it.aRecordWentOn(.somebodyAskedForIt)
        it.somebodyPressedPause()

        it.theQueueMovedOn()

        #expect(it.isPaused)
    }

    /// The same problem through a seek: the seek started playback of a paused record.
    @Test func aSeekOnAPausedRecordLeavesItPaused() {
        var it = Playback()
        it.aRecordWentOn(.somebodyAskedForIt)
        it.somebodyPressedPause()

        it.theRecordWasMovedThrough()

        #expect(it.isPaused)
    }

    /// Picking a speaker is not asking to hear anything, in either direction.
    @Test func pickingASpeakerMovesNeitherWay() {
        var playing = Playback()
        playing.aRecordWentOn(.somebodyAskedForIt)
        playing.movedToTheRoom()
        #expect(playing.doing == .playing)

        var paused = Playback()
        paused.aRecordWentOn(.somebodyAskedForIt)
        paused.somebodyPressedPause()
        paused.movedToTheRoom()
        #expect(paused.isPaused, "somebody paused who picks a speaker has asked for nothing")
    }

    /// A press on the speaker's own controls is a person's action. It is only used while the sound
    /// is going to that speaker.
    @Test func theRoomIsOnlyListenedToWhileTheSoundGoesThere() {
        var casting = Playback()
        casting.aRecordWentOn(.somebodyAskedForIt)
        casting.movedToTheRoom()
        casting.theRoomSaid(playing: false)
        #expect(casting.isPaused, "a hand on the speaker is somebody asking")

        var home = Playback()
        home.aRecordWentOn(.somebodyAskedForIt)
        home.theRoomSaid(playing: false)
        #expect(home.doing == .playing, "a room this player is not sending to is not news")
    }

    /// A record that starts where nothing was playing plays, whoever started it. Nobody has asked
    /// for silence, so there is none to keep. The machinery may make this change, and the test
    /// states it explicitly.
    @Test func aRecordGoingOnWhereThereWasNothingPlays() {
        var it = Playback()
        it.aRecordWentOn(.carryOnAsBefore)
        #expect(it.doing == .playing)
    }
}
