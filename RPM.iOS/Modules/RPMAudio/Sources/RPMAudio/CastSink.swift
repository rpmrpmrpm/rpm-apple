import Foundation
import AVFAudio
import RPMCast
import os

/// Casting, as a sink.
///
/// **Casting is not a special case.** The engine has one source and one destination. This class
/// moves the destination to a speaker and nothing above it changes. A queue advances because the
/// engine advances it. A record is levelled because the pump applies the gain before it hands
/// anything over.
///
/// This follows the design of the Uno head (`LpcmCastSink`) and the desktop app. Do not tap the
/// live graph and mute the handset instead: sending audio to two places makes the sound distort
/// when a speaker connects, because one of those places is a real-time thread with a deadline
/// every few milliseconds. The engine stops its own output device instead. See `RoomFeed`.
///
/// What is sent is linear PCM in a WAV wrapper. The Default Media Receiver plays it natively and
/// the engine already holds it. It needs about 1.4 Mbit/s, which is small on a home network, and
/// it saves running an encoder in real time on the phone.
public final class CastSink: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// Six seconds. Long enough to cover a short network interruption, short enough that a pause
    /// is heard when it is pressed and not six seconds later.
    private let ring = PcmRing(seconds: 6)

    private let server: CastServer
    private let engine: PcmEngine

    public init(engine: PcmEngine) {
        self.engine = engine
        self.server = CastServer(ring: ring)
    }

    /// Starts serving, and answers the address to hand the speaker.
    ///
    /// **The engine stops playing on this phone at the same moment.** It is not muted while it
    /// keeps rendering. See ``RoomFeed``.
    public func begin(from seconds: Double, named: String) async throws -> URL {
        let url = try await server.start()

        let room = RoomFeed(ring: ring, named: named)
        room.failed = { [weak self] said in self?.failed?(said) }

        self.room = room
        engine.send(to: room, from: seconds)

        return url
    }

    /// Takes our audio off the receiver and creates the address of the next stream.
    ///
    /// **Cutting the old stream and naming the new one are one step**, and the order inside it
    /// decides whether the speaker switches cleanly or jumps and then stutters.
    ///
    /// *Why cut at all.* One endless stream lets a record follow the previous one with no gap,
    /// which is right when a record ends. It is wrong when the user presses next. At that moment
    /// the receiver holds several seconds of the ring, whatever is in the socket, and its own
    /// buffer (half a minute on a Chromecast), and all of it is the song being skipped. With one
    /// stream there is no way to tell the receiver to drop that audio. So the server answers for
    /// a new stream name and no longer for the old one. The receiver gets the new name in a fresh
    /// LOAD, drops what it held, and fetches the new stream. The C# heads create a new name on
    /// **every** track change (`CastSink.Begin`, `LpcmCastSink.Begin`, each with a
    /// `Guid.NewGuid()`). This head keeps one stream when nothing asks for a change, and creates
    /// a new name only when the user asked for one.
    ///
    /// *Why this runs before the engine gets the new track.* The ring has one reader. If the old
    /// connection stays open while the new track is decoded into the ring, the old and new
    /// readers take turns, and the new track arrives in fragments. Emptying the ring does not
    /// help, because the old reader would then consume from the emptied ring.
    ///
    /// *Why the caller must also release the session.* From here until the LOAD comes back, the
    /// room is empty and reports that. Without knowing the reason, that looks like a stop at the
    /// speaker. See `RoomStream`.
    ///
    /// The ring is not emptied here. `PcmEngine.play` empties it through ``RoomFeed/begin(at:)``
    /// when it puts the new source on. That is the same moment, and the only place that knows at
    /// which second the new track starts.
    public func handOver() async -> URL? {
        // **The feed is told first, as part of the same step.** Between the cut and the next
        // `begin`, its counters describe a stream that the receiver no longer has: `written` keeps
        // climbing while `reported` stopped when the connection did. The pacer would read the
        // growing difference as a room that has stopped answering, and after 30 seconds of that it
        // would bring the music back to the phone, although the user only pressed next. See
        // ``RoomFeed/takenBack()``.
        room?.takenBack()

        return await server.nowServing()
    }

    /// Whether the receiver has actually come for the stream that is live now.
    ///
    /// **Accepting a LOAD is not the same as fetching the stream.** This is the one failure that
    /// nothing else on this side can see. If the receiver never reports a position, the pacer
    /// falls back to the ring, and its stall watch does not run in that state. The pump then
    /// waits on a full ring, the room stays silent for ever, and no error is raised. The desktop
    /// checks this with a twenty-second watch on the same fact (`CastSink.LoadAsync`), and that
    /// watch reads this value.
    public func wasFetched() async -> Bool { await server.fetched }

    // ── the cover, which the server answers for ──

    /// Says that a cover is coming. A receiver that asks for the cover address before the picture
    /// has been read then waits, and is not told that this record has no cover.
    ///
    /// **Every call must be followed by ``nowShowing(_:)``**, also when reading the picture
    /// failed. Passing nil means "this record has no cover", which is a valid answer. See
    /// `CastServer.expectCover`.
    public func expectCover() async { await server.expectCover() }

    /// The cover itself, or nil for a record without one.
    public func nowShowing(_ jpeg: Data?) async { await server.nowShowing(jpeg) }

    /// Where a receiver fetches the cover from. The caller supplies the name: see
    /// `CastServer.coverAddress(named:)`.
    public func coverAddress(named key: String) async -> URL? {
        await server.coverAddress(named: key)
    }

    /// The receiver's position in the stream it is playing, by its own clock, or nil before it
    /// has reported anything.
    ///
    /// **This is not the same value as ``heard``**, which is a position in the record. A screen in
    /// another room runs its own clock from this value, so it must use the receiver's counting.
    /// Otherwise the running time on a television is wrong by the offset where the stream started.
    /// See `CastNowPlaying.streamAt`.
    public var inTheStream: Double? { room?.inTheStream }

    /// The position the **speaker** reports in the record, or nil before it has reported anything.
    public var heard: Double? { room?.heard }

    /// Records the speaker's last report, in seconds into the stream it is playing.
    public func says(_ seconds: Double) { room?.says(seconds) }

    /// Whether the user paused playback.
    ///
    /// **A paused speaker reports a position that does not move**, and `RoomFeed` watches for
    /// exactly that to decide the room has gone away. When it knows about the pause, it waits.
    /// If it is not told, it treats the paused room as lost after 30 seconds and brings the music
    /// back to the phone, although the user only pressed pause.
    public var paused: Bool {
        get { room?.paused ?? false }
        set { room?.paused = newValue }
    }

    /// Called when the speaker stops taking audio, so the player can bring the sound back to the
    /// phone and not stay on a stalled cast.
    public var failed: (@Sendable (String) -> Void)?

    /// Waits until the ring holds enough audio for a receiver to start on.
    ///
    /// **This is the same problem as priming the player node, one layer further out.** A receiver
    /// does not begin until it has buffered a few seconds. It cannot build that buffer from a
    /// stream that arrives at real-time speed, so what is waiting when it connects is all it will
    /// have. If it is told to fetch too early, it stutters for the first few seconds and then
    /// settles.
    ///
    /// It gives up after `within` instead of waiting for ever: a paused player never fills
    /// the ring, and a speaker that starts with little audio is better than a button that does
    /// nothing.
    public func fill(to seconds: Double = 4, within: Duration = .seconds(6)) async {
        let until = ContinuousClock.now.advanced(by: within)

        while waiting < seconds, ContinuousClock.now < until {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Hands the sound back to the phone, continuing from the position the room had reached.
    public func end() async {
        volume.close()
        let at = room?.heard

        // **This must come first.** The pump may be waiting inside the room's pacing for a
        // speaker that is about to stop answering, and nothing else here can release a task that
        // is already waiting there.
        room?.release()
        room = nil
        try? engine.comeHome(at: at ?? 0)

        await server.stop()
        ring.empty()
    }

    /// The destination the engine is pointed at while this is connected.
    private var room: RoomFeed?

    // ── the one knob, which belongs to the speaker ──

    /// The volume exchange with the speaker. **It is not a gain**: the samples leave here at full
    /// scale and the level goes over the control channel. It moves the speaker's own volume, so
    /// everyone in that room hears the change.
    private lazy var volume = CastVolume { [weak self] level in
        guard let turn = self?.turn else { return }
        await turn(level)
    }

    /// Sends the level to the speaker. Set by whoever holds the connection.
    public var turn: (@Sendable (Double) async -> Void)?

    /// The user changed the volume on this device.
    public func turnTheRoom(to level: Int) {
        // Send the level only once there is a stream. A level sent before the LOAD would set a
        // room that was at 20% to whatever the handset's volume is.
        volume.set(level, live: room != nil)
    }

    /// The speaker reported its volume. Returns the level to follow, or nil when the report is
    /// only the echo of our own change.
    public func roomMovedTo(_ level: Double?) -> Int? { volume.adopt(level) }

    /// How much audio was discarded because nothing read it. If this keeps rising while a speaker
    /// is connected, the speaker has stopped reading without reporting it. If it rises before a
    /// speaker connects, that is normal: the ring keeps only the most recent seconds.
    public var dropped: Int { ring.dropped }

    /// How many seconds are sitting in the ring.
    ///
    /// **This is not how far the room is behind.** In steady state it is close to zero: the
    /// network takes the audio much faster than real time, so the delay sits inside the
    /// receiver's own buffer, where nothing here can see it. The correct playback position while
    /// casting is the position the **receiver** reports. The Uno head takes the engine's clock
    /// from the sink for this reason. This head does not do that yet.
    public var waiting: Double {
        guard ring.perSecond > 0 else { return 0 }
        return Double(ring.held) / Double(ring.perSecond)
    }

}
