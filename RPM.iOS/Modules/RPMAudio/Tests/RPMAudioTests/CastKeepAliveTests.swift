import Foundation
import AVFAudio
import Testing
import RPMCast
@testable import RPMAudio

/// The silence that keeps the app running while a speaker plays.
///
/// **These tests check the bookkeeping only.** Whether the silence really stops iOS from
/// suspending a locked phone needs a real speaker, a real cast and a locked screen. A test
/// process cannot do that. The tests check that the silence starts when the sound leaves the
/// phone and stops when the sound comes back. A later edit could break this without anyone
/// noticing.
@Suite("The silence that keeps a cast alive", .serialized)
struct CastKeepAliveTests {

    @Test func stoppingOneThatNeverRanIsNothing() {
        let awake = CastKeepAlive()
        awake.stop()

        #expect(awake.wanted == false)
        #expect(awake.rendering == nil)
    }

    @Test func startingAsksForItAndStoppingTakesItBack() {
        let awake = CastKeepAlive()

        awake.start()
        #expect(awake.wanted)

        awake.stop()
        #expect(awake.wanted == false)
        #expect(awake.rendering == nil)
    }

    /// The guard. The pair is held and reused, not made fresh each time. A second engine
    /// started here would be a render thread that nothing holds and that no `stop` can reach.
    /// The check also holds when nothing started, because `nil === nil` is true on a machine
    /// with no output device.
    @Test func aSecondStartIsNotASecondEngine() {
        let awake = CastKeepAlive()

        awake.start()
        let first = awake.rendering

        awake.start()
        #expect(awake.rendering === first)

        awake.stop()
        #expect(awake.rendering == nil)
    }

    @Test func oneStopUndoesAnyNumberOfStarts() {
        let awake = CastKeepAlive()

        awake.start()
        awake.start()
        awake.start()
        awake.stop()

        #expect(awake.wanted == false)
        #expect(awake.rendering == nil)
    }

    // ── and the wiring, which is the thing worth pinning ──

    /// The engine turns the silence on and off, so moving the destination is the only way to
    /// change it. This test checks both halves.
    @Test func theSilenceIsFittedWhileTheSoundIsAway() {
        let engine = PcmEngine(normalize: NormalizeContext())
        #expect(engine.keepingAwake == false)

        let room = RoomFeed(ring: PcmRing(seconds: 1), named: "a speaker")
        engine.send(to: room, from: 0)
        #expect(engine.keepingAwake)

        // `comeHome` can throw, for example on a machine with no output device. A `defer` in it
        // stops the silence either way, so the error is ignored here.
        try? engine.comeHome(at: 0)
        #expect(engine.keepingAwake == false)

        room.release()
    }

    /// **The silence is off while the sound is paused.** This is a real requirement. On iOS,
    /// the lock screen takes its play or pause state from whether the app's audio session is
    /// playing audio. If silence kept running during a pause, the lock screen would show a
    /// pause control for a room that is paused. See `PcmEngine.pause`.
    @Test func theSilenceStopsWhileTheRoomIsPaused() throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        let room = RoomFeed(ring: PcmRing(seconds: 1), named: "a speaker")

        engine.send(to: room, from: 0)
        #expect(engine.keepingAwake)

        engine.pause()
        #expect(engine.keepingAwake == false)
        #expect(room.paused)

        try engine.resume()
        #expect(engine.keepingAwake)
        #expect(room.paused == false)

        try? engine.comeHome(at: 0)
        room.release()
    }
}
