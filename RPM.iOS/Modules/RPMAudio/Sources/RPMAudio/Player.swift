import Foundation
import AVFoundation
import RPMKit
import RPMLibrary
import RPMRadio
import RPMCast
import os

/// The player.
///
/// **Changes here must account for every event that can change which track is current.**
/// Half of those events do not come from the app: the engine finishes a track on its own
/// clock, the lock screen sends a command from another process, and a phone call takes the
/// audio session away and gives it back. A player that is one track behind is not slow. It
/// is playing the wrong song.
///
/// The engine is `AVQueuePlayer` holding at most two items, the one playing and the one
/// after it. This makes the changeover gapless without the app owning a buffer: the
/// framework has already opened the next file by the time the current one ends. Only two
/// items are held, not the whole queue, because every item is built from a **signed**
/// address, and an address signed an hour ago for a track nobody reached has expired.
@MainActor
@Observable
public final class Player {
    private let source: any StreamSource

    /// The first seconds of records this phone has already been near, so that starting
    /// one of them is a file read instead of a signature and a connection.
    private let shelves: any ShelfSource
    private let urls: StreamUrlCache

    /// Whether a track's record is marked classical. Asked when the track is handed to
    /// the engine, so the answer is the one that is true at that moment.
    private let classical: ClassicalRecord

    /// The records downloaded to this phone. Asked before anything is signed: a track
    /// with a copy here is read from the file whatever the network is doing.
    private let copies: any PhoneCopies

    /// The computers on the home network. Asked after ``copies`` and before anything is signed.
    private let nearby: any NearbyCopies

    /// The home-network address each open feed was started from, by queue position. A feed that
    /// fails from one starts over from the cloud instead of being retried at the same address.
    private var nearbyFeeds: [Int: URL] = [:]

    /// Whether a socket may be opened at all. Read at the moment a track is chosen, so
    /// the answer is the current one, not one that was pushed here earlier.
    private let reach: NetworkReach

    /// What rate to ask for. The store answers with what it can actually serve.
    public var kilobits: Int = 320

    /// The listener's levelling setting.
    ///
    /// **Held by the engine, not here.** The pump reads it for every block it levels,
    /// on its own thread, so there is one copy and it belongs to the engine. A second copy
    /// here could disagree with it. Setting it reaches the record already playing, and
    /// ``levelling`` is worked out again so that what the player reports matches.
    public var normalize: NormalizeContext {
        get { sound.normalize }
        set {
            sound.normalize = newValue
            levelling = level(current)
        }
    }

    private static let log = Logger(subsystem: "com.rpm.player", category: "audio")

    /// The queue: this app's own engine. It is what makes the drawn stages, casting
    /// and two decks possible. See `PcmEngine`.
    private let sound: PcmEngine

    /// Whatever is being downloaded for the queue, by the position it belongs to.
    private var feeds: [Int: TrackFeed] = [:]

    /// **A station, and only a station.**
    ///
    /// It stays on AVFoundation for one reason: the titles. A station announces what
    /// it is playing in the ICY bytes on the socket, and `AVPlayerItemMetadataOutput`
    /// reads them. The Uno head has a thousand lines of hand-written reader for this
    /// instead, which this app avoids. The cost is that a station's sound never enters
    /// the engine, so it cannot be cast.
    private let radio = AVQueuePlayer()

    /// - Parameter cover: where a record's cover comes from when it has to be shown on a
    ///   screen in another room. **No default**: with a default, casting could publish no
    ///   cover at all and nothing would report it. See ``RoomCover``. A head with no
    ///   pictures to give answers `{ _ in nil }`, which is a stated answer instead of an
    ///   omitted one.
    ///
    /// - Parameters:
    ///   - copies: what is downloaded. **No default**: a player built without it streams
    ///     every downloaded record, which works until the phone goes offline and then
    ///     plays nothing.
    ///   - reach: the gate's reading of the network.
    ///   - levelling: the listener's levelling setting as stored. **No default**: a
    ///     player built without it would level by the default until something set it,
    ///     and a launch where nothing did would ignore the setting with no sign of it.
    ///   - levelsClassical: whether records marked classical are levelled too, as
    ///     stored. No default, for the same reason.
    ///   - classical: whether a track's record is marked classical. **No default**: a
    ///     player built without it levels every classical record. A head with no marks
    ///     to give answers `{ _ in false }`.
    public init(source: any StreamSource, shelves: any ShelfSource,
                copies: any PhoneCopies, nearby: any NearbyCopies, reach: NetworkReach,
                levelling: NormalizeMode,
                levelsClassical: Bool,
                classical: @escaping ClassicalRecord,
                cover: @escaping RoomCover,
                urls: StreamUrlCache = StreamUrlCache()) {
        self.sound = PcmEngine(normalize: NormalizeContext(mode: levelling,
                                                           includeClassical: levelsClassical))
        self.classical = classical
        self.source = source
        self.shelves = shelves
        self.copies = copies
        self.nearby = nearby
        self.reach = reach
        self.cover = cover
        self.urls = urls

        radio.actionAtItemEnd = .advance

        // **Must stay on.** This player only plays stations, and a station needs the wait.
        // A station is somebody else's server with no file behind it to read ahead into,
        // so at the moment it is tuned there is nothing buffered at all. With the wait
        // off, `play()` forces a start on an empty buffer, the start fails, and **the
        // rate falls to zero and stays there**. When the stream is finally ready,
        // AVFoundation says `desired rate is 0.0; not restarting`, and nothing else asks
        // for sound. The user taps a station and gets silence.
        radio.automaticallyWaitsToMinimizeStalling = true
        // Nothing is drawn from this player, so there is no reason for it to keep a
        // video pipeline running.
        radio.allowsExternalPlayback = false

        watchTheEngine()
    }

    // ── what is playing ──

    public private(set) var queue: [CloudTrack] = [] { didSet { relevelTheQueue() } }

    /// Where in the queue the **engine** is, or nil when there is nothing at the
    /// playing position: an empty queue, or a queue whose playing track was taken out of
    /// it.
    ///
    /// Optional instead of a position that happens to point at nothing, because
    /// "stopped with a queue still on screen" is a real state, and a removal produces
    /// it. See ``QueueEdit``, which answers in the same shape.
    ///
    /// Written from two places and no others: the observer below, in answer to what
    /// the engine says it is playing, and a queue edit, which changes the list around
    /// the playing position without moving it.
    public private(set) var index: Int?

    /// The track ids of the list the queue was last started with: an album, a playlist,
    /// a shuffle. Set only when a list from outside the queue replaces it, and cleared
    /// with the queue. Next, Previous, a queue row and the queue's own shuffle leave it
    /// alone, so the edits stay visible against it. See ``hasChangesAhead``.
    private var started: [String] = []

    /// Whether the user changed the songs still to come: added one, dragged one, removed
    /// one or shuffled them. Asked when a tap would replace the queue, and worked out
    /// from the queue at that moment. See ``QueueEdit/hasChangesAhead(queue:current:started:)``.
    public var hasChangesAhead: Bool {
        QueueEdit.hasChangesAhead(queue: queue.map(\.rpmId), current: index, started: started)
    }

    /// The earliest position in the queue **that this session has actually played**, and
    /// therefore the top of the list that is shown.
    ///
    /// Starting an album at track ten puts the whole record in the queue, because
    /// pressing back must have somewhere to go. The nine tracks above it were never
    /// played, though, and a list that shows them above the playing track would say
    /// they were played and skipped. So the queue keeps the whole record, and this says
    /// where the session began.
    ///
    /// **It only ever moves down**, and only when playback really reaches that position:
    /// pressing back at track ten plays track nine, and track nine is then part of
    /// the session. It is derived from the playing position, not remembered at the start,
    /// so the answer is the same whatever order the starts arrive in.
    ///
    /// It is also a count: it is exactly how many entries are hidden above the top of
    /// the list, which a queue edit has to keep correct.
    public private(set) var earliest = 0

    public private(set) var isPlaying = false

    /// Set from the tap until the engine is holding a source: the address signed, the
    /// item built, the queue seated. It covers everything the player does before the
    /// engine has anything to wait on.
    public private(set) var starting = false

    /// The engine has a source and has been asked for sound, but none is coming out
    /// yet. `waitingToPlayAtSpecifiedRate` is AVFoundation's own name for it. It is a
    /// better signal than "the position is still zero", which is also true of a track
    /// that is paused at the start.
    public private(set) var opening = false

    /// **Whether anything is being waited on before sound can come out**: the period
    /// in which a play key shows a spinner.
    ///
    /// Two states, not one. ``starting`` is the work this player does to get a
    /// track open, and ``opening`` is the engine holding a source that has not
    /// produced its first block. A key that watched only the second would stay a triangle
    /// through the whole network round trip, which is the slow part.
    public var isBusy: Bool { starting || opening }

    /// **Whether the player has been asked for sound**, as against whether any is
    /// coming out yet: what a play key and the lock screen draw.
    ///
    /// ``isPlaying`` is false for the whole second a track takes to open. That is
    /// correct, but it is not what the key should show: it would turn a pause that was
    /// just pressed back into a play key. On the lock screen, where play and pause are
    /// separate commands and not one toggle, the next press would do the opposite of
    /// what the key says. See ``Transport``.
    public var wantsToPlay: Bool { transport.wantsToPlay(starting: starting, loaded: loaded) }

    /// What the engine is holding, kept as a fact this player **stores** and not as a
    /// question it asks.
    ///
    /// **The engine cannot be observed and should not be.** `PcmEngine` is a lock and a
    /// render thread, and a play key is a view. So the engine's answer is read into this
    /// at every point that can change it, and once on each tick, and the key draws this.
    ///
    /// If the key asked the engine directly, it would draw the right answer once and
    /// never be told to draw it again, because SwiftUI cannot watch `sound.isPaused`.
    /// **The value must change when the cause is outside the key as well as inside it**:
    /// a seek, a route change, an interruption and the lock screen all change it
    /// without anybody pressing the key.
    private var loaded = Loaded.nothing

    /// Play and pause, and what to do with one pressed before there is anything to
    /// press it against.
    private var transport = Transport()

    /// Re-reads the engine and reports that what the player is doing has changed.
    ///
    /// **The single entry point.** Everything that starts, stops, pauses or replaces the
    /// sound goes through here, so no path has to remember to keep ``loaded`` current,
    /// and the lock screen and the play key are updated by the same call because they
    /// draw the same fact.
    private func playbackChanged() {
        readTheEngine()
        onPlaybackChanged?()
    }

    /// Stores the engine's answer only when it has changed. This class is `@Observable`,
    /// so assigning the same value again would still redraw everything that watches it,
    /// four times a second for as long as a record plays.
    private func readTheEngine() {
        let now = holding
        if loaded != now { loaded = now }
    }

    /// When the tap that is still being answered happened.
    ///
    /// It lets the wait be **measured**: on the simulator on Wi-Fi a start takes about
    /// a fifth of a second, and the number that matters can only be read on a real
    /// phone. Cleared by the first sound, so a start that never arrives leaves nothing
    /// to report twice.
    private var awaited: Date?

    /// What the engine is holding. This is the only thing ``Transport`` needs: it
    /// does the deciding, and this reports what is true.
    private var holding: Loaded {
        if station != nil, !stationIsOnTheEngine {
            guard radio.currentItem != nil else { return .nothing }
            return radio.timeControlStatus == .paused ? .paused : .playing
        }

        guard sound.playing != nil else { return .nothing }

        // **One question, asked of the object that knows.** Do not rebuild the answer
        // from separate checks (is there a source, is it paused, is it playing, is it
        // priming). While casting, each of those has a second answer, and they must be
        // read in the right order: asked-for silence before priming, priming counted as
        // playing, the node consulted only when there is one. Getting that order wrong
        // in any place causes ordering faults in the cast. See ``Playback``.
        return sound.playback.loaded
    }

    /// **The rate that is actually playing**, as the store answered it, not
    /// the one that was asked for.
    ///
    /// Nil while an address is being signed and for a station. Blank in both cases: a
    /// wrong number here is worse than none, because the line is only useful if it can
    /// be trusted.
    public private(set) var playingKilobits: Int?
    public private(set) var position: Duration = .zero
    public private(set) var duration: Duration = .zero

    /// Set when a track could not be started, and cleared by the next thing that
    /// works. A music failure is shown as a sentence, not a crash.
    public private(set) var trouble: String?

    /// Why the last start did not happen. This is a different question from the
    /// sentence about it: a person reads the sentence, and a retry rule would be
    /// written against this. `.none` after a start that worked, and after one
    /// that was abandoned because something else was chosen.
    public private(set) var failure: PlaybackFailure = .none {
        // **On the property, not at the six places that write it.** When the last
        // network failure happened is a fact about the failure, and a line that every
        // caller has to remember to write is a line one of them will forget.
        didSet { failedAt = failure.blamesTheNetwork ? Date() : nil }
    }

    /// When the current failure happened, or nil when the current failure is not one the
    /// network could fix.
    private var failedAt: Date?

    /// How long after a record stopped for lack of a network it is still the record
    /// the listener is waiting for.
    ///
    /// There is a limit on purpose. A train that goes into a tunnel and comes out two
    /// minutes later is a short break, and starting the music again is what anybody would
    /// want. A phone that has been in a pocket since the morning is different: music
    /// that starts by itself in a meeting because the Wi-Fi came back is something
    /// nobody asked for.
    private static let stillWaiting: TimeInterval = 120

    /// What the record is being levelled by, for anything that wants to report it.
    public private(set) var levelling: NormalizeDecision = .none

    public var current: CloudTrack? {
        guard let index, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    public var hasNext: Bool {
        guard let index else { return false }
        return index + 1 < queue.count
    }

    public var hasPrevious: Bool {
        guard let index else { return false }
        return index > 0
    }

    /// **Whether the listening is over**: no track at the playing position, nothing waiting
    /// behind it, and no station on.
    ///
    /// This is the one question a screen asks to know that listening is finished. It is
    /// one question and not two because the stop key and the last record of a queue
    /// ending are the same ending, and a shell that watched only the key would leave the
    /// player standing over a record that had finished by itself.
    ///
    /// **This is not the same question as "is there anything to show".** A queue whose
    /// playing track was taken out of it has no track at the playing position and is not
    /// over: the rest of it is still there to be played, and somebody editing a list has
    /// not asked to be sent anywhere.
    public var isOver: Bool {
        current == nil && station == nil && queue.isEmpty
    }

    /// Called whenever the current track changes, so an app can fetch its cover for
    /// the lock screen without this object knowing what a picture is.
    ///
    /// Never called directly: `announce` is the only way in. It makes one
    /// tap give one announcement, not three, and a second record give one, not none.
    public var onTrackChanged: ((CloudTrack?) -> Void)?

    /// Which track the last announcement was about.
    ///
    /// **Stored, not read back from the queue.** What counts as news is a
    /// different TRACK, not a different index. A record started from the top while
    /// another one is already playing from the top gets the same number, and an
    /// announcement made by index would be silent for it: the cover and the lock screen
    /// would keep showing the earlier record. Comparing what is at the playing position
    /// against the queue does not work either, because `play` replaces the queue BEFORE
    /// it settles, so by then the old index already points at the new record. This is
    /// the only thing that still remembers what was announced.
    private var toldAbout: String?

    /// Announces that a track is playing, once.
    ///
    /// `play` settles twice: once on what was tapped, and again once the address is
    /// signed and the rate is known. Both are the same record.
    private func announce(_ track: CloudTrack?) {
        guard toldAbout != track?.rpmId else { return }

        toldAbout = track?.rpmId
        onTrackChanged?(track)
    }

    /// What has been listened to, off the tick. Its own type because the rule about what counts as
    /// a play is shared with the desktop and belongs in one place: see ``PlayCounter``.
    private let plays = PlayCounter()

    /// Called when a listen ended and counted. The app writes it to the play log; this side does not
    /// hold the log, so that a player can be built in a test without one.
    public var onPlayCounted: ((PlayCounter.Counted) -> Void)?

    /// Ends the listen in hand, for an app going to the background or being closed with a record
    /// on. Without it the last record of a session is never counted, and that is the one the
    /// listener was actually listening to.
    ///
    /// **It also hands out the radio heard so far**, without ending that listen: the station plays
    /// on in the background, and iOS may close the app before it changes. See ``StationCounter``.
    public func settlePlay() {
        if let counted = plays.settle() { onPlayCounted?(counted) }
        if let heard = stationsHeard.handOut() { onStationHeard?(heard) }
    }

    /// What has been heard on the radio, off the tick. The rule is shared with the desktop's
    /// `RadioTally`; see ``StationCounter``.
    private let stationsHeard = StationCounter()

    /// Called when some radio listening is ready to be written down. The app writes it to the station
    /// log, as it writes plays to the play log.
    public var onStationHeard: ((StationCounter.Heard) -> Void)?

    /// Called when the rate or the position **jumps**.
    ///
    /// The lock screen is given a position and a rate and works out the rest itself,
    /// so it needs to be told when one of those two stops being true, not four times a
    /// second. Sound starting, stopping or stalling is one such event; a seek is the other.
    /// The lock screen can interpolate everything in between, and posting on a timer would
    /// make the media daemon redraw a clock that it already draws.
    public var onPlaybackChanged: (() -> Void)?

    // ── the radio ──

    /// The station on the engine, or nil when what is playing is the library.
    ///
    /// **A station uses the same player as everything else.** This is why it is here
    /// and not in a separate tuner: the strip at the foot of the screen, the lock screen
    /// and the headset button then work on the radio without knowing it is the radio.
    /// The desktop makes the same choice for the same reason.
    public private(set) var station: RadioStation?

    /// What the station last announced, **exactly as it said it**. Empty until it
    /// says something, and always empty on an HLS station, which carries no ICY
    /// metadata at all.
    ///
    /// Raw, not split into a pair here: one screen wants the artist on its own
    /// line and another wants the whole text on one line, and a string that is already
    /// joined cannot be taken apart again. `IcyTitle` splits on a spaced dash, and the
    /// joining character is not one.
    public private(set) var announced = ""

    /// Whether the playing position is on a station and not on a record.
    public var onTheRadio: Bool { station != nil }

    /// Whether the last thing put on was a station.
    ///
    /// **It outlives the station.** Stopping ends a listening session, and the screen
    /// that puts the user back where they were listening asks after the music has
    /// already stopped, when `station` is nil along with everything else. So the
    /// kind of listening is remembered even though the listening is not: a stopped
    /// record returns to the library, and a stopped station returns to the dial.
    public private(set) var wasTheRadio = false

    /// Whether what is playing is on AVFoundation and not on this app's engine.
    /// **Only an HLS station is**. Everything else, records and ordinary stations
    /// alike, goes through the engine.
    private var onAvFoundation: Bool { station != nil && !stationIsOnTheEngine }

    /// Tells the speaker to start or to stop.
    ///
    /// The stream never stops arriving, so a receiver left playing through a pause
    /// plays out its buffer and then sits on a stalled stream. It is told to stop, and
    /// the pump stops filling. See `PcmEngine.pause`.
    private func tellTheRoom(playing: Bool) {
        guard let link, let app = castApp, let session = room.session else {
            // **Owed, not dropped.** There is no session during a changeover, and
            // a key pressed then would go nowhere without any report, so the user
            // presses pause and the speaker plays on. See
            // `RoomStream.owe(playing:)`.
            if isCasting {
                room.owe(playing: playing)
                Self.log.notice("""
                    the room cannot be told \(playing ? "play" : "pause", privacy: .public) yet \
                    (\(String(describing: self.room.stage), privacy: .public)); owed
                    """)
            }
            return
        }

        // **Dated before it is sent.** Everything the room reports between here and the
        // key arriving describes a room that has not been told yet. See `RoomStream.told`.
        room.toldIt()

        Task {
            // Logged either way. A `try?` would swallow the reason a key never reached
            // the speaker, and the reason is the one thing worth knowing.
            let word = playing ? "play" : "pause"
            do {
                if playing { try await link.play(session: session, on: app.transportId) }
                else { try await link.pause(session: session, on: app.transportId) }
                Self.log.notice("the room was told \(word, privacy: .public)")
            } catch {
                Self.log.error("the room was not told \(word, privacy: .public): \(String(describing: error), privacy: .public)")
            }

            // Answered or failed, the key is no longer on its way, and the poll may ask
            // under a date again. This runs on every path: if it were skipped, every
            // answer from the room would be ignored for ever.
            room.heardBack()

        }
    }

    /// What the room is holding of ours, and the only thing its words are read against.
    ///
    /// **Read `RoomStream` before changing anything in the cast.** A receiver says the
    /// same words for a hand on the speaker and for the middle of a track change, and
    /// this is what tells them apart.
    private var room = RoomStream() {
        didSet { roomAtAGlance.value = (room.turns, room.stamp, room.session) }
    }

    /// The three numbers the poll needs, readable **without the main actor**.
    ///
    /// **The poll must not hop onto the main actor to read these.** If it did, everything
    /// it does afterwards would wait behind whatever the main actor is doing. Searching a
    /// large shared library takes seconds of main-actor time, and the result would be:
    ///
    /// 1. the poll cannot run, so `sink.says(at)` is never called;
    /// 2. so the room's reported position stops moving, though the room is playing;
    /// 3. so the pacer sees the pump running further and further ahead of a speaker that
    ///    appears stuck, and parks the pump in `RoomFeed.take`: **the music stops**;
    /// 4. thirty seconds of a position that has not moved is `RoomFeed`'s definition of
    ///    a speaker that has gone away: **a long pause of nothing**;
    /// 5. so the session falls over and the sound comes back to the phone: **the phone
    ///    starts playing**.
    ///
    /// All of these symptoms would come from typing in a search box. The playing
    /// position already avoids the main actor, and so must this.
    private let roomAtAGlance = Snapshot((0, Int?.some(0), Int?.none))

    /// Called when a station is tuned, so an app can put it on the lock screen.
    public var onStationChanged: ((RadioStation?) -> Void)?

    private var listening: AVPlayerItemMetadataOutput?
    private var heard: MetadataHeard?

    /// Tunes a station in.
    ///
    /// No signing, no look-ahead and no queue: a station is one address that does not
    /// expire and does not end. It does share the generation with a record: a station
    /// tuned while a track is still being signed must not be replaced by that track
    /// when its address arrives.
    public func tune(_ station: RadioStation) {
        tune(station, again: false)
    }

    /// Whether a station whose stream dropped is being tuned in again. The screens show this
    /// instead of what the station announces.
    public private(set) var reconnecting = false

    /// How many times in a row the station that is on now has been tuned in again. Back to zero once
    /// it plays, and on every tune that somebody asked for.
    private var reconnects = 0

    /// The waits before each attempt, as the desktop's `RadioStreamSource` waits: half a second,
    /// then doubling to fifteen. The last one repeats.
    static let reconnectWaits: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2),
                                             .seconds(4), .seconds(8), .seconds(15)]

    /// How many attempts are made before the station is reported as offline.
    static let mostReconnects = 8

    /// - Parameter again: whether this is the player tuning a dropped station in again, which
    ///   keeps the count of attempts, as against somebody asking for it, which starts the count over.
    private func tune(_ station: RadioStation, again: Bool) {
        if !again {
            reconnects = 0
            reconnecting = false
        }
        guard let url = URL(string: station.streamUrl) else {
            trouble = Loc.get("Rpm_Radio_CannotPlay")
            return
        }

        generation += 1
        transport.forgotten()
        starting = false
        playingKilobits = nil
        awaited = Date()

        radio.removeAllItems()
        stopTheQueue()

        queue = []
        index = nil
        earliest = 0
        started = []
        position = .zero
        duration = .zero
        levelling = .none
        trouble = nil

        self.station = station
        announced = ""
        wasTheRadio = true

        // **A station is a source, so it goes through the engine like a record.** The
        // Uno head does the same, because a station can be cast only when it is a
        // source too. On its own player it would be a second output, which cannot be
        // cast, cannot be levelled and cannot be drawn.
        //
        // The exception is HLS, which the Uno head also leaves on AVFoundation, for the
        // same reason as here: it is a playlist of segments, not a stream of bytes, and
        // nothing in this code reads one.
        if station.isHls {
            tuneAwayFromTheEngine(url, station: station)
        } else {
            tuneOnTheEngine(url, station: station)
        }

        announce(nil)
        onStationChanged?(station)

        // After the queue is put down, so the timer finds no track to hold the next
        // record back behind.
        changeSleepTimer {
            $0.stationTuned()
            $0.somebodyAskedForSound(now: .now)
        }
    }

    /// The ordinary station: bytes off a socket, through the same decoder and the same
    /// engine as a record, which is what lets it be cast.
    private func tuneOnTheEngine(_ url: URL, station: RadioStation) {
        let feed = StationFeed()
        tuned = feed
        opening = true

        let mine = generation

        feed.announced = { [weak self] said in
            Task { @MainActor in
                guard let self, self.generation == mine else { return }
                self.announced = said.trimmingCharacters(in: .whitespacesAndNewlines)
                self.onStationChanged?(self.station)
            }
        }

        feed.stopped = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == mine else { return }
                self.opening = false
                self.stationDropped(station, generation: mine)
            }
        }

        feed.start(url)

        Task { [weak self] in
            // The same wait a record gets (800 polls of 25 ms, 20 s). After 20 seconds the
            // connection is not slow, it is not going to answer.
            for _ in 0..<800 {
                guard let self, self.generation == mine else { feed.stop(); return }
                if feed.pcm.ready || feed.trouble != nil { break }
                try? await Task.sleep(for: .milliseconds(25))
            }

            guard let self, self.generation == mine, feed.pcm.ready else { return }

            await MainActor.run {
                // Unity gain: a station has no loudness measurement.
                do {
                    try self.sound.play(feed.pcm, id: Self.stationId, loudness: .unmeasured,
                                        because: .somebodyAskedForIt)
                }
                catch {
                    self.trouble = Loc.get("Rpm_Radio_StationCannotPlay", station.name)
                    self.opening = false
                    self.playbackChanged()
                    return
                }

                self.opening = false
                self.reconnects = 0
                self.reconnecting = false
                self.playbackChanged()
            }
        }
    }

    /// A station's stream stopped. While it is still the station meant to play, it is tuned in
    /// again after a wait, up to ``mostReconnects`` times. After the last attempt the station is
    /// reported as offline.
    ///
    /// Each attempt checks, when its wait is over, that nothing was tuned, stopped or paused in
    /// the meantime: each of those changes the generation.
    private func stationDropped(_ station: RadioStation, generation mine: Int) {
        // If somebody paused it, nobody is waiting for it, so the station is reported as
        // offline without tuning in again. A stream that never opened, or that dropped
        // while playing, is still meant to play.
        let pausedOnPurpose = holding == .paused || transport.pausePending
        guard !pausedOnPurpose, reconnects < Self.mostReconnects else {
            reconnecting = false
            trouble = Loc.get("Rpm_Radio_StationOffline", station.name)
            playbackChanged()
            return
        }

        let wait = Self.reconnectWaits[min(reconnects, Self.reconnectWaits.count - 1)]
        reconnects += 1
        reconnecting = true
        playbackChanged()

        Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, self.generation == mine, self.station?.uuid == station.uuid else { return }
            self.tune(station, again: true)
        }
    }

    /// HLS, which stays on AVFoundation. **A foreign source**, as the Uno head calls it:
    /// it plays outside the engine, so it cannot be cast and nothing draws it.
    private func tuneAwayFromTheEngine(_ url: URL, station: RadioStation) {
        let item = AVPlayerItem(url: url)
        // A station stalls more often than a record, and for longer: it is somebody
        // else's server and there is no file behind it to read ahead into.
        watchTheBuffer(of: item)
        listen(to: item)
        watchForTrouble(item, station: station)

        radio.insert(item, after: nil)
        // Always unity gain. A station is not levelled: there is no loudness reading for
        // something that has not been measured, and a guessed one would make a quiet
        // station that the listener takes for a broken phone.
        radio.volume = 1
        radio.play()
    }

    /// The station on the engine, while there is one.
    private var tuned: StationFeed?

    /// The id a station goes into the engine under. **Not a queue index**: there is no
    /// queue while a station is on, and anything comparing this against an index is asking
    /// the wrong question.
    private static let stationId = -1

    /// Whether what is playing is a station the engine is holding, as opposed to one
    /// on AVFoundation.
    private var stationIsOnTheEngine: Bool { tuned != nil }

    /// The station ends when the library starts: anything that puts a record on ends
    /// the radio listening. The desktop applies the same rule.
    private func leaveTheRadio() {
        guard station != nil else { return }

        station = nil
        announced = ""
        stopListening()

        tuned?.stop()
        tuned = nil

        onStationChanged?(nil)
    }

    /// Reads what the station announces, with AVFoundation separating the metadata from
    /// the audio.
    ///
    /// The Uno head pulls the ICY bytes out of the socket itself, because it has no
    /// framework that does this. Here there is one, and a hand-written reader beside it
    /// would give a second answer to the same question.
    private func listen(to item: AVPlayerItem) {
        stopListening()

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let heard = MetadataHeard { [weak self] said in
            Task { @MainActor in
                guard let self else { return }
                self.announced = said?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                // Reported as the other station path does: what a station has
                // just announced is the second line on the lock screen, and nothing
                // else about the station has changed to trigger an update.
                self.onStationChanged?(self.station)
            }
        }

        // The delegate is called on the queue it is given, which is not the main actor.
        // A dispatch queue and an actor are not the same guarantee: the hop to the main
        // actor is inside the callback, not assumed by it.
        output.setDelegate(heard, queue: DispatchQueue(label: "rpm.icy"))
        item.add(output)

        listening = output
        self.heard = heard
    }

    private func stopListening() {
        listening = nil
        heard = nil
        watchingItem = nil
    }

    /// A station that will not open reports that it failed.
    ///
    /// **Only a station**, and that is on purpose. A track that fails is one row
    /// of a queue and the player moves past it. A station is the whole of what was
    /// asked for, and a strip that sits there saying nothing looks like a broken
    /// phone. The directory is run by volunteers and has many addresses that stopped
    /// answering years ago, so this is the ordinary case, not the rare one.
    private func watchForTrouble(_ item: AVPlayerItem, station: RadioStation) {
        watchingItem = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }

            let said = (item.error as NSError?)?.localizedDescription

            Task { @MainActor in
                guard let self, self.station?.uuid == station.uuid else { return }
                self.trouble = said ?? Loc.get("Rpm_Radio_Offline")
            }
        }
    }

    private var watchingItem: NSKeyValueObservation?

    // ── the orderings ──

    /// **Which start is the live one.** A signed address is a network round trip. If the
    /// user taps one record and then another before the first address arrives, the first
    /// one arrives to find a different record playing. The value is captured before the
    /// first await and checked after it.
    private var generation = 0

    /// How many seeks there have been. Not a generation of its own: a seek deliberately does
    /// NOT bump the generation, because a signature in flight for this same track is still the
    /// live one. See ``playSession``, which is the one place the two are added.
    private var seeks = 0

    /// How many times the stream at the playing position has been started again: every play,
    /// every stop, every station, every seek.
    ///
    /// **It tells a seek from a track that simply plays on**, which the position alone cannot
    /// do, so the listen tally uses it to close off a stretch. The generation covers the first
    /// three because each of them is a new stream. A seek is a new stream too (see
    /// ``seek(to:)``), but it is the one that does not change the generation.
    public var playSession: Int { generation &+ seeks }

    /// Which position has already been handed to the engine as the look-ahead, so a
    /// track is not enqueued twice.
    private var lookingAhead: Int?

    private var watching: [NSKeyValueObservation] = []

    /// Watching the item that is playing, which changes with every track. Separate
    /// from `watching`, which belongs to the engine and lives as long as this object.
    private var watchingBuffer: [NSKeyValueObservation] = []
    private var stalled: NSObjectProtocol?

    /// Whether the buffer ran out under a track that was playing, and this player is
    /// the one that has to start it again.
    private var recovering = false

    /// How many attempts the track that is playing has had. A record that stops instead of
    /// ending is opened again, and this limits that. See ``Retries``.
    private var retries = Retries()
    /// The playing position's own clock. It is a task and not AVFoundation's periodic
    /// observer, because records play through the app's own engine, not AVFoundation.
    private var ticking: Task<Void, Never>?

    // ── starting ──

    /// How the track a start opens arrives in the engine.
    private enum Arrival {
        /// Playing: every start that somebody or the queue asked for.
        case plays
        /// Paused, standing where it was put: a queue put back from the last run
        /// (``cue(_:at:position:)``). Nobody asked for sound, so none comes.
        case standsPaused
    }

    /// Where a list handed to ``startPlaying(_:from:because:list:arriving:)`` came from.
    private enum ListFrom {
        /// From outside the queue: it replaces the queue and becomes ``started``.
        case outside

        /// The queue itself, in its own order or reordered. ``started`` is kept, so the
        /// user's edits still count.
        case theQueue
    }

    /// Replaces the queue with a list from outside it and plays from a position in it.
    ///
    /// Internal, not public: the app goes through ``replacing(with:from:tapped:)`` and
    /// ``start(_:)``, which ask first when the user changed the queue. Tests call this
    /// directly.
    func play(_ tracks: [CloudTrack], from asked: Int, because why: Playback.Start) async {
        await startPlaying(tracks, from: asked, because: why, list: .outside, arriving: .plays)
    }

    /// Loads `tracks` with the one at `at` standing paused at `position`: the queue a TV
    /// kept from its last run, put back as it was left (the Android TV's LastQueue). Nothing
    /// plays until play is pressed, and play then resumes it where it stood.
    ///
    /// **It goes through the start path, with the pause owed on arrival**, not a start followed
    /// by a pause from outside. A pause pressed before the start has begun is dropped by the
    /// start (``Transport/starting()``), and one pressed after the source arrives lets a moment
    /// of sound through. See ``Transport/pausePending``.
    public func cue(_ tracks: [CloudTrack], at: Int, position: Duration) async {
        guard tracks.indices.contains(at) else { return }

        await startPlaying(tracks, from: at, because: .carryOnAsBefore, list: .outside,
                           arriving: .standsPaused)

        // Only on the same record: offline, the start may have stepped on to the next one
        // the device holds, and that one starts at its top.
        if position > .zero, index == at { _ = seek(to: position) }
    }

    /// Plays a list from a position in it. Every start goes through here.
    ///
    /// - Parameters:
    ///   - why: whether somebody asked for this. **Not defaulted**: this is reached both
    ///     by a tap on a track and by the queue advancing on its own, and the difference
    ///     is whether a pause survives it. See ``PcmEngine/Start``.
    ///   - list: whether `tracks` comes from outside the queue or is the queue itself.
    ///     Not defaulted either: Next passing `.outside` would erase the user's edits.
    ///   - arriving: whether the track plays when it arrives. Not defaulted: a start that
    ///     forgot to say would play a queue that was only being put back.
    private func startPlaying(_ tracks: [CloudTrack], from asked: Int, because why: Playback.Start,
                              list: ListFrom, arriving: Arrival) async {
        guard tracks.indices.contains(asked) else { return }

        // Where an earlier network stop left off. It is only meant for the restart that
        // reads it (see ``pickUpWhereItStopped()``), so every other start clears it.
        stoppedAt = nil

        // **Offline, only what is on the phone can play.** The first track from the one
        // asked for that has a copy here, so a queue that mixes downloaded and streamed
        // records plays the downloaded ones and steps over the rest. If there is none at
        // all, the offline sentence is shown and nothing is started.
        guard let from = playable(in: tracks, from: asked) else {
            leaveTheRadio()
            generation += 1
            stopTheQueue()
            isPlaying = false
            starting = false
            opening = false
            failure = .offline
            trouble = failure.said
            playbackChanged()
            return
        }

        leaveTheRadio()
        generation += 1
        let mine = generation

        // Choosing a track means somebody asked to hear it, so anything remembered
        // against the last one is dropped.
        transport.starting()
        // A queue being put back owes its pause from here, so the source is paused the
        // moment it arrives (`transport.arrives()` below).
        if arriving == .standsPaused { _ = transport.pause(starting: true, loaded: .nothing) }
        starting = true
        recovering = false
        if why == .somebodyAskedForIt { somebodyAskedForSound() }
        let began = Date()
        awaited = began

        // Cleared however this ends, including the two early exits below: a flag left
        // set would be a spinner that never stops.
        defer { if mine == generation { starting = false } }

        // **A new list is a new session.** The same list handed back means the playing
        // position moves inside the list already on the screen, which is what `next` and
        // `previous` do. This is worked out from the tracks and not from a flag that the
        // callers would have to remember to set, since every one of them calls this
        // same function.
        let carriedOn = tracks.count == queue.count
            && zip(tracks, queue).allSatisfy { $0.rpmId == $1.rpmId }

        queue = tracks
        if !carriedOn { earliest = from }

        // Set together with the queue, so an offline start that exits above leaves both unchanged.
        if list == .outside { started = tracks.map(\.rpmId) }
        trouble = nil
        playingKilobits = nil
        wasTheRadio = false

        // **`index` is not set here.** `settle` sets it, and it decides whether this
        // is news by whether it changed. If it were assigned first, every start would
        // look like the track that was already current, so the cover and the lock
        // screen would never be told about any of them.
        stopTheQueue()

        // **Before the network, not after it.** The screen shows what was tapped. A title
        // that waited for a header to arrive would leave the player showing the last
        // record for as long as the store takes to answer.
        settle(on: from)

        // Taken now, with the track the feed is about to be opened for. After the awaits
        // below the queue may have been edited, and `queue[from]` could be another track
        // or past the end.
        let loud = loudness(of: tracks[from])

        // **The room is released first, and the order matters.**
        //
        // Putting a source on the engine empties the ring and starts filling it with
        // the new track, and the connection feeding the speaker is still attached to
        // that ring. There is one ring and one reader. Two readers do not each get a
        // copy: they take turns, a piece each, and the speaker plays the new track
        // in fragments. The result is a skip that jumps about and then stutters.
        //
        // So the connection is cut here, the ring is refilled with nobody reading, and the
        // receiver gets the new address once there is something behind it. See
        // `handTheRoomTheNewTrack`.
        //
        // **The room is empty from this line until the LOAD lands.** The poll must know
        // this at the same moment, or it reads the empty room as a stop at the speaker and
        // stops the music. That is why the cut and the forgetting are one call. See
        // `RoomStream`.
        let roomsNextStream = isCasting ? await takeTheRoomsStream() : nil

        guard let feed = await open(at: from, generation: mine) else { return }
        guard mine == generation else { feed.stop(); return }

        do { try sound.play(feed.pcm, id: from, loudness: loud, because: why) }
        catch {
            trouble = PlaybackFailure.unknown.said
            return
        }

        // **Through `playbackChanged()`, now that the engine holds the new record.** This
        // replaces the sound, and ``playbackChanged()`` is where everything that replaces
        // it is reported. If this were left to the tick, the key would keep drawing the
        // pause of the previous record until the next reading, a quarter of a second of
        // "paused" after the user picked a record.
        playbackChanged()

        // **The room is handed a new stream.** Nothing happens when the sound is on the
        // handset. This is before the pause below and before the look-ahead, because until
        // it has happened the speaker is still playing the last record.
        await handTheRoomTheNewTrack(roomsNextStream, generation: mine)

        // Settled again now that the address is signed: the rate is only known once the store
        // has answered, and it is the one field that could not be filled in above.
        settle(on: from)

        // A press that arrived while the address was being signed. It is applied here
        // and not thrown away, as "there is nothing to pause" would do.
        //
        // **It is reported**, because it is a pause that nobody has just pressed. The key
        // draws what was read from the engine at the points that change it, and a pause
        // applied on arrival is one of them.
        if transport.arrives() {
            sound.pause()
            playbackChanged()
        }

        // **Before the look-ahead, not after it.** The look-ahead signs the track
        // after this one. If the start were not marked finished until that completed, the
        // spinner would stay up for the whole of this track.
        starting = false

        // A track that played has put its troubles behind it, so a stumble half an
        // hour from now gets its full three attempts.
        retries.forget()

        Self.log.notice("track away in \(Date().timeIntervalSince(began), format: .fixed(precision: 3))s")

        await lookAhead(after: from, generation: mine)
    }

    /// Starts what is playing again from where it had got to.
    ///
    /// It is for one case: the audio server restarting. Everything that was talking to
    /// it then holds a handle to nothing, and the item in the engine will not make a
    /// sound however long it is left. See `RemoteControl`, which hears about the restart.
    public func pickUpWhereItStopped() async {
        if let station { tune(station); return }

        guard let at = index else { return }

        let got = stoppedAt ?? position
        await startPlaying(queue, from: at, because: .carryOnAsBefore, list: .theQueue, arriving: .plays)

        // Only on the same record. Offline, the start may have stepped on to the next one
        // on the phone, and that one starts at its top.
        if got > .zero, index == at { seek(to: got) }
    }

    /// Where a record that stopped for lack of a network had got to. See ``theLineWentAway()``.
    private var stoppedAt: Duration?

    /// The network came back, and a record is standing here that stopped because it was gone.
    ///
    /// Only the failures that waiting can fix are handled, and only while somebody could still
    /// be waiting: see ``blamesTheNetwork`` and ``stillWaiting``. Everything else is left as
    /// it is, with its sentence still on the screen.
    public func theLineCameBack() {
        guard !isPlaying, failure.blamesTheNetwork,
              let stopped = failedAt,
              Date().timeIntervalSince(stopped) < Self.stillWaiting
        else { return }

        // A fresh three attempts. The budget this track spent was spent against a network that
        // is not the one it is about to be asked of. Keeping it would mean that a record that
        // stumbled twice underground never plays again.
        retries.forget()

        Task { await pickUpWhereItStopped() }
    }

    /// The network went away while a streamed record was playing.
    ///
    /// **It stops the record instead of letting it run out.** The read-ahead holds some
    /// seconds of audio, and a record that plays on for a while and then stops in the
    /// middle of a phrase is worse than one that stops when the phone says it is offline.
    /// The queue and the playing position stay where they are, with the reason on the
    /// screen, so ``theLineCameBack()`` can carry on from the same place.
    ///
    /// A record read from the phone is left alone: it does not need the network.
    public func theLineWentAway() {
        guard !onTheRadio, let track = current, copies.copy(of: track.rpmId) == nil,
              isPlaying || isBusy
        else { return }

        // First, so an open still in progress cannot start the record after this.
        generation += 1

        // Kept apart from `position`, which the tick reads off the engine and which is
        // zero as soon as the engine holds nothing.
        stoppedAt = position
        stopTheQueue()

        isPlaying = false
        starting = false
        opening = false
        recovering = false
        failure = .offline
        trouble = failure.said

        playbackChanged()
    }

    /// The first position from `from` that can be played now: any of them while the
    /// gate is open, and only the ones with a copy on the phone while it is shut.
    private func playable(in tracks: [CloudTrack], from: Int) -> Int? {
        guard !reach.now.isOnline else { return from }
        return tracks.indices[from...].first { copies.copy(of: tracks[$0].rpmId) != nil }
    }

    // ── replacing the queue ──

    /// What replacing the queue with `tracks` would cost, worked out before anything
    /// changes.
    ///
    /// Clear when the user changed nothing still to come, and when `tracks` is the queue
    /// itself, which moves inside it and loses nothing. Otherwise the answer is a question,
    /// and its two starts are the only way through.
    public func replacing(with tracks: [CloudTrack], from: Int, tapped: Tapped) -> Replacing {
        let replace = QueueStart(.replace(tracks, from: from))

        guard hasChangesAhead, !tracks.map(\.rpmId).elementsEqual(queue.map(\.rpmId)) else {
            return .clear(replace)
        }

        let keep: QueueStart
        switch tapped {
        case .song:
            let song = tracks.indices.contains(from) ? [tracks[from]] : []
            keep = QueueStart(.playNow(song, from: 0))
        case .list:
            keep = QueueStart(.playNow(tracks, from: from))
        }

        return .asks(QueueQuestion(replace: replace, keep: keep))
    }

    /// Starts what ``replacing(with:from:tapped:)``, or an answer to its question, gave.
    public func start(_ start: QueueStart) async {
        switch start.what {
        case .replace(let tracks, let from):
            await startPlaying(tracks, from: from, because: .somebodyAskedForIt, list: .outside, arriving: .plays)
        case .playNow(let tracks, let from):
            await playNow(tracks, from: from)
        }
    }

    /// Puts `tracks` after the playing track and plays the one at `from`; the rest of the
    /// queue follows them. With nothing playing they go to the top of the shown queue.
    ///
    /// The insert and the start run with no suspension between them, and the start closes
    /// every feed and empties the engine before its first await, so nothing keyed by the
    /// old positions is left to read them.
    private func playNow(_ tracks: [CloudTrack], from: Int) async {
        guard tracks.indices.contains(from) else { return }

        let at = index.map { min($0 + 1, queue.count) } ?? min(earliest, queue.count)
        queue.insert(contentsOf: tracks, at: at)

        await startPlaying(queue, from: at + from, because: .somebodyAskedForIt, list: .theQueue, arriving: .plays)
    }

    /// Plays the queue's own row at `at`. A move inside the queue, so it never asks.
    public func jump(to at: Int) async {
        await startPlaying(queue, from: at, because: .somebodyAskedForIt, list: .theQueue, arriving: .plays)
    }

    /// Puts the whole queue in another order and plays it from the top.
    ///
    /// The queue is reordered, not replaced: ``started`` stays as it was, so the new order
    /// counts as a change and the next tap that would replace the queue asks first.
    public func shuffleTheQueue() async {
        guard !queue.isEmpty else { return }
        await startPlaying(queue.shuffled(), from: 0, because: .somebodyAskedForIt, list: .theQueue, arriving: .plays)
    }

    // ── moving ──

    public func next() async {
        guard hasNext, let index else { return }

        // The look-ahead has already signed the address and started the bytes, so
        // this is a start with the network work already done. It is not the gapless path:
        // gapless is a record ENDING into the next one, and a press on the key
        // asks for the rest of this record to stop.
        await startPlaying(queue, from: index + 1, because: .somebodyAskedForIt, list: .theQueue, arriving: .plays)
    }

    /// Back a track, or back to the start of this one.
    ///
    /// Three seconds is the usual limit and it matches what people mean: pressing
    /// back once during a song means "play this again", and pressing it in the first
    /// moments means "I meant the one before".
    public func previous() async {
        if position > .seconds(3) {
            seek(to: .zero)
            return
        }

        guard hasPrevious, let index else { seek(to: .zero); return }
        await startPlaying(queue, from: index - 1, because: .somebodyAskedForIt, list: .theQueue, arriving: .plays)
    }

    /// The headphone pinch, the steering-wheel button and the key in the app.
    ///
    /// Reads what the **engine** is holding and not a stored flag: this is reached
    /// from three places at once, and a handler that decided from a value captured
    /// before it was queued would toggle the wrong way.
    public func toggle() {
        if reopensWhatStopped() { return }
        apply(transport.toggle(starting: starting, loaded: holding))
    }

    /// Play pressed over a record that stopped for lack of a network: the engine holds
    /// nothing, so there is nothing to resume, and the record is opened again where it
    /// stood. Offline, that finds the next record on the phone, or reports that the phone
    /// is offline.
    private func reopensWhatStopped() -> Bool {
        guard !starting, holding == .nothing, current != nil, failure.blamesTheNetwork
        else { return false }

        Task { await pickUpWhereItStopped() }
        return true
    }

    /// Play, meaning play. The lock screen and Control Centre send this and ``pause``
    /// as two separate commands, and a toggle is the wrong answer to either. Pressed
    /// while a track is opening, it takes back a pause pressed a moment before, and
    /// otherwise does nothing: the track is already on its way.
    public func resume() {
        if reopensWhatStopped() { return }
        apply(transport.play(starting: starting, loaded: holding))
    }

    /// Pause, meaning pause. Pressed while a track is still opening, it is remembered
    /// and applied the moment the source arrives.
    public func pause() {
        apply(transport.pause(starting: starting, loaded: holding))
    }

    private func apply(_ move: TransportMove) {
        switch move {
        // Nothing is waiting for the buffer any more: somebody asked for silence.
        // **Whichever thing is actually playing.** A station can be on AVFoundation or on
        // the engine, and a cast means neither alone: the speaker has to be told as well,
        // because nothing local is running to pause. Sending the key to the wrong one
        // gives a key that does nothing.
        case .pause:
            recovering = false
            onAvFoundation ? radio.pause() : sound.pause()

            // **Set here as well as by the engine.** This is a duplicate, kept on purpose
            // until there is evidence that it is not needed: `PcmEngine.pause`
            // sets this on the room it holds, and removing this line was part of a change
            // after which pausing stopped reaching the speaker. Remove it only when a log
            // shows which line is responsible.
            sink?.paused = true
            tellTheRoom(playing: false)

        case .resume:
            somebodyAskedForSound()

            if onAvFoundation {
                radio.play()
            } else {
                do { try sound.resume() }
                catch {
                    // **The engine would not start again.** The app was away long
                    // enough for the system to take the graph down, or the route
                    // belongs to another app now. Otherwise the playing position would
                    // move over silence (the lock screen would show a clock counting
                    // and nothing coming out), so the record is opened again where it
                    // stood instead.
                    Self.log.notice("the engine would not resume; opening the record again")
                    Task { [weak self] in await self?.pickUpWhereItStopped() }
                }
            }

            sink?.paused = false
            tellTheRoom(playing: true)

        // Remembered or withdrawn: nothing happens to the audio, and the key still
        // changes, because it draws what was asked for. Changing `transport`
        // is what makes that happen.
        case .nothing, .remember, .forget: break
        }

        // **iOS must be told, because that is all a pause is to anything outside
        // this app.** The engine does not tell the lock screen or Control Centre anything.
        // They show what they were last given, so a pause that nobody announced
        // leaves a pause key over silence and a clock still counting. `onPlaybackChanged`
        // is wired straight to `RemoteControl.showPosition`, which sets both the rate and
        // the playback state from `wantsToPlay`.
        //
        // This runs for every case, including the three that change no sound at all.
        // The key draws what was **asked for**, and a remembered pause has changed that.
        playbackChanged()
    }

    /// Moves the playing position.
    ///
    /// **A downloaded stream has no seek of its own.** It goes forwards and only
    /// forwards, so a seek is the same track asked for again from another byte, which
    /// is what `TrackFeed.moveTo` does. Nothing is reopened for a station, which has
    /// no position to move through in the first place.
    @discardableResult
    public func seek(to where_: Duration) -> Double? {
        guard !onTheRadio, let at = index, let feed = feeds[at] else { return nil }
        guard let landed = feed.moveTo(where_.seconds) else { return nil }

        let mine = generation

        // Taken before the casting path's await, while `at` is still this track.
        let loud = loudness(of: queue[at])

        // A new stretch for anything counting listening: what is heard from here on was not heard
        // before it. It is told where the seek landed and not left to the next tick, which on the
        // casting path still reads the old position for a moment. See PlayCounter.
        seeks &+= 1
        plays.seeked(to: landed)

        // Set now, whatever the sound is doing: the position bar shows where the user
        // put it, and a bar that waits for the network would spring back.
        position = .seconds(landed)

        // **A seek is a new stream too**, for the same reason a track change is: what
        // the room holds is the seconds that were just moved away from, and it will play
        // every one of them before it reaches the ones asked for.
        //
        // On the handset this is three lines in a row. With a speaker on the end of it, the
        // order matters and every step is an await, so it is one task and not
        // three: the room is released, *then* the engine is handed the new source,
        // *then* the room is given the address. With two separate tasks there was a race:
        // the cut could land after the engine had already started refilling the ring,
        // so the old connection and the new track would each take a piece of the same ring.
        guard isCasting else {
            try? sound.play(feed.pcm, id: at, from: landed, loudness: loud,
                            because: .carryOnAsBefore)
            lookingAhead = nil
            Task { await lookAhead(after: at, generation: mine) }
            playbackChanged()
            return landed
        }

        Task { [weak self] in
            guard let self else { return }

            let next = await takeTheRoomsStream()
            guard mine == generation else { return }

            try? sound.play(feed.pcm, id: at, from: landed, loudness: loud,
                            because: .carryOnAsBefore)
            await handTheRoomTheNewTrack(next, generation: mine)

            // Starting the node again dropped what was queued behind it, so the record
            // after this one has to be put back.
            lookingAhead = nil
            await lookAhead(after: at, generation: mine)

            // The one change the lock screen cannot work out from a rate.
            playbackChanged()
        }

        return landed
    }

    /// Stop: the queue and the station are both put down, and the playing position goes
    /// back to nothing.
    ///
    /// **This ends a session and is not a transport key**, which is why it is here
    /// and not beside pause. What remains afterwards is ``isOver``, the fact the
    /// screens read to take the strip off the foot of the app and return the listener
    /// to where the listening started.
    ///
    /// **It does not stop the room.** Stopping the music is not the same as taking it off
    /// the speaker, and the Uno head's own `Stop` leaves a cast session standing for
    /// the same reason: the next thing played goes to the same speaker.
    ///
    /// The generation is bumped **first**, so a signature already in flight cannot
    /// start a track just after the key was pressed. Without it, a record that was
    /// opening when stop was pressed would arrive afterwards and start playing on its own.
    public func stop() {
        generation += 1
        transport.forgotten()
        leaveTheRadio()
        reconnects = 0
        reconnecting = false

        radio.pause()
        radio.removeAllItems()
        stopTheQueue()

        queue = []
        index = nil
        earliest = 0
        started = []
        position = .zero
        duration = .zero
        isPlaying = false
        starting = false
        opening = false
        recovering = false
        playingKilobits = nil

        // The item these were watching has been released.
        watchingBuffer = []
        stalled.map(NotificationCenter.default.removeObserver)
        stalled = nil
        levelling = .none
        trouble = nil

        announce(nil)

        // The end of a session ends the timer that was set for it. This is after the queue is
        // cleared, so there is no track left to hold the next record back behind.
        changeSleepTimer { $0.turnOff() }

        // **The room is told too, but it is not told to stop.** The cast is deliberately
        // left standing (the Uno head's `Stop` does the same), so the next thing played
        // goes to the same speaker. But the stream the room is fetching stops being filled
        // the moment the engine stops, and a receiver left playing an empty stream sits on a
        // stalled one until it gives up. When paused, it waits.
        sink?.paused = true
        tellTheRoom(playing: false)

        // The engine does not tell the lock screen anything: it shows what it was
        // last given. `announce` takes the entry down, and this reports the change to
        // anything watching the transport and not the track: the strip at the foot
        // of the app, and the key it draws.
        playbackChanged()
    }

    /// Everything given back: signing out, and signing in as somebody else.
    ///
    /// It stops playback, and then clears the two things that belong to the person and not
    /// to the music: the room they were casting to, and the signed addresses of their
    /// files. A phone handed to someone else must not keep either.
    public func forget() {
        // **Before the stop, not after it.** The screens watch the stop, and
        // what they ask next is where the listening came from. A station remembered
        // past a sign-out would send the next person to the dial.
        wasTheRadio = false

        stop()

        Task { await stopCasting() }
        urls.forget()
    }

    // ── the sleep timer ──

    /// When the player pauses by itself. See ``SleepTimer``.
    ///
    /// Held here and not by a screen, so it keeps counting while the player view is closed
    /// and the app is in the background. Written only through ``changeSleepTimer(_:)`` and
    /// the two places the timer fires.
    public private(set) var sleepTimer = SleepTimer()

    /// Sleeps until the deadline of a timed setting. Replaced on every change to the
    /// timer. What it does when it wakes is decided by the setting at that moment.
    private var sleepWake: Task<Void, Never>?

    public func setSleepTimer(_ choice: SleepTimer.Choice) {
        changeSleepTimer { $0.set(choice, now: .now) }
    }

    public func addSleepTime(_ more: Duration) {
        let left = trackLeft
        changeSleepTimer { $0.add(more, now: .now, trackLeft: left) }
    }

    public func turnOffSleepTimer() {
        changeSleepTimer { $0.turnOff() }
    }

    /// Time left on the timer at `now`, or nil when it is off. For a timer waiting for
    /// the end of the track, this is the track's own time left.
    public func sleepTimeLeft(at now: ContinuousClock.Instant) -> Duration? {
        sleepTimer.left(now: now, trackLeft: trackLeft)
    }

    /// How much of the current track is left, or nil on a station and with
    /// nothing playing.
    private var trackLeft: Duration? {
        guard !onTheRadio, current != nil else { return nil }
        return max(.zero, duration - position)
    }

    /// Changes the timer, and when that changed anything, brings the wake task and the
    /// engine in line with it.
    ///
    /// **The single entry point.** The change is applied to a copy and written back only when
    /// it differs: the timer is observed, and writing the same value again redraws
    /// everything that watches it.
    private func changeSleepTimer(_ change: (inout SleepTimer) -> Void) {
        var timer = sleepTimer
        change(&timer)
        guard timer != sleepTimer else { return }

        sleepTimer = timer
        wakeAtTheSleepDeadline()
        handOverOrHoldBackTheNextRecord()
    }

    private func somebodyAskedForSound() {
        changeSleepTimer { $0.somebodyAskedForSound(now: .now) }
    }

    private func wakeAtTheSleepDeadline() {
        sleepWake?.cancel()
        sleepWake = nil

        guard case .at(let deadline) = sleepTimer.setting else { return }

        sleepWake = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.sleepDeadlineArrived()
        }
    }

    private func sleepDeadlineArrived() {
        var timer = sleepTimer
        guard timer.deadlineArrived(now: .now) else { return }

        sleepTimer = timer
        sleepWake = nil

        // The transport's own pause: a track still opening is paused the moment it
        // arrives, and a player already paused or stopped is left as it is.
        pause()
    }

    /// Whether the next record is kept back from the engine, so that the engine runs out when
    /// the track playing ends and ``queueRanOut(_:)`` can pause there.
    ///
    /// **Only on the handset.** While casting, the decoder runs up to eight seconds ahead
    /// of the speaker, so the engine runs out that far before the room does and a pause
    /// there would cut the end of the song. With a speaker connected the next record is
    /// handed over as usual, and ``settleFromTheEngine(_:)`` pauses when the room reaches
    /// it.
    private var holdsBackTheNextRecord: Bool { sleepTimer.endsWithTheTrack && !isCasting }

    /// Takes the next record back from the engine when the timer now waits for the end of
    /// the track, and hands it over again when it no longer does.
    private func handOverOrHoldBackTheNextRecord() {
        guard !onTheRadio, let at = index else { return }

        if holdsBackTheNextRecord {
            // False when the pump has already moved on to the next record: that audio is
            // in front of the node, and the changeover in `settleFromTheEngine` pauses.
            if sound.dropWhatIsNext(behind: at) { lookingAhead = nil }
            return
        }

        // Not while a start is in progress: `play` hands the next record over itself when
        // it finishes, and one handed over before the start's own source would be
        // dropped by it while still marked as handed over.
        guard lookingAhead == nil, !starting else { return }

        let mine = generation
        Task { await lookAhead(after: at, generation: mine) }
    }

    /// Moves the queue on to the next record by itself, because the one playing ended
    /// or cannot go on. **Paused there when the timer was waiting for this track to
    /// end**: a pause before the start carries over, because a record that the queue moves
    /// on to by itself keeps whatever was asked of the one before (see
    /// ``Playback/aRecordWentOn(_:)``).
    private func carryOn(after at: Int) {
        var timer = sleepTimer
        let sleeps = timer.trackEnded()

        if sleeps {
            sleepTimer = timer

            // `apply` and not `pause()`: the engine has just run out, and what the
            // transport would read off it to decide is not what this depends on.
            apply(.pause)
        }

        Task {
            await startPlaying(queue, from: at + 1, because: .carryOnAsBefore, list: .theQueue, arriving: .plays)

            // The start brought the audio device back up to hold the next record, which
            // stays paused. The device is taken down again, because iOS reads a running
            // device as playing, both on the lock screen and for keeping the app
            // awake all night. Skipped when anything asked for sound in the meantime.
            if sleeps, sound.isPaused { sound.pause() }
        }
    }

    // ── editing the queue ──

    /// Takes tracks out of the queue while it is playing.
    ///
    /// The arithmetic is ``QueueEdit``'s and is not repeated here, because that is
    /// where it can be tested: every position removed from above the playing track
    /// moves its index down one, removing several at once moves it down several times,
    /// and removing the playing track itself gives a different outcome again.
    ///
    /// **Removing the track that is playing stops the music**, instead of moving
    /// the playing position onto whatever moved into the slot. The desktop gives the
    /// same answer.
    public func remove(_ positions: [Int]) {
        let plan = QueueEdit.planRemoval(count: queue.count, current: index,
                                         remove: positions)
        guard !plan.removals.isEmpty else { return }

        // **Before the queue moves under it.** Everything opened and everything handed
        // to the engine is keyed by the position it had when it was opened, and this is
        // the last moment those keys are still valid. See ``reseat(from:)``.
        let wasAt = index

        // Highest first, as planned: each removal must not shift the ones still to
        // come.
        for at in plan.removals { queue.remove(at: at) }
        index = plan.current

        // `earliest` is how many entries are hidden above the list, so a removal from
        // among them takes one off that count. Nothing on the screen can be one of
        // them, because they are the rows nobody is shown, but `remove` is public.
        earliest -= plan.removals.filter { $0 < earliest }.count

        plan.removedCurrent ? stopBecauseItWentAway() : reseat(from: wasAt)
    }

    /// Puts songs into the queue directly after whatever is playing.
    ///
    /// **Nothing starts and nothing stops.** A song sent up next is a song asked for
    /// later: the playing record keeps its place and its position, and only what
    /// follows it changes. This matches the Uno head's `PlaybackService.InsertNext`,
    /// including its answer for an empty deck: with nothing playing this is an append,
    /// which is what "next" means to a queue that has not started, and it still does not
    /// begin playing.
    ///
    /// The record that was to follow is no longer the follower, so what was already
    /// handed to the engine for that slot is taken back by `reseat(from:)`, the same
    /// function every other queue edit uses. The Uno head clears its own engine's queued
    /// next record here for the same reason.
    public func insertNext(_ tracks: [CloudTrack]) {
        guard !tracks.isEmpty else { return }

        // Past the current row, or at the end where there is no current row. Nothing
        // playing is an empty deck, and inserting at zero there would put these in
        // front of a queue that has not started, and not after a record that is not
        // playing.
        let at = index.map { min($0 + 1, queue.count) } ?? queue.count
        queue.insert(contentsOf: tracks, at: at)

        // Everything went in AFTER the playing position, so the playing record's number and
        // the count of rows above the session are both unchanged.
        reseat(from: index)
    }

    /// Puts songs at the end of the queue. Nothing starts and nothing stops: with nothing playing
    /// they wait in the queue, as ``insertNext(_:)``'s do.
    public func append(_ tracks: [CloudTrack]) {
        guard !tracks.isEmpty else { return }
        queue.append(contentsOf: tracks)

        // Everything went in at the end, so the playing record keeps its number. The record
        // after it changes only when the queue ended at the playing position.
        reseat(from: index)
    }

    /// Drags one track to another place in the running order.
    ///
    /// Nothing stops: the song coming out of the speaker is unaffected by where it
    /// now sits in the list.
    public func move(from: Int, to: Int) {
        let plan = QueueEdit.planMove(count: queue.count, current: index,
                                      from: from, to: to)
        guard !plan.isNothing else { return }

        // As in ``remove(_:)``: the old number of the playing record, read while it is
        // still the number that everything else is keyed by.
        let wasAt = index

        let carried = queue.remove(at: plan.from)
        queue.insert(carried, at: plan.to)
        index = plan.current

        // A drag inside the list changes nothing about what is above it. A drag that
        // crosses the top does: a hidden track dragged into the list means one fewer
        // hidden, and the reverse means one more. The lists do not offer the reverse
        // (see `QueueRows.drop`, which will not land a row in the past), but the count
        // is kept correct anyway, because a number that is only right while nobody does
        // the other thing will be wrong later.
        if plan.from < earliest && plan.to >= earliest { earliest -= 1 }
        else if plan.from >= earliest && plan.to < earliest { earliest += 1 }

        reseat(from: wasAt)
    }

    /// Puts what is still to come in another order.
    ///
    /// **Ahead of the playing position and nowhere else.** `QueueEdit.whatIsComing` holds
    /// that rule, and the drag and the rows use it too, so this call site cannot forget it
    /// and shuffle the playing record out of its own place.
    ///
    /// Nothing before the playing position moves, so the playing record keeps its number and
    /// `earliest` still counts the same rows. What does change is the record after it,
    /// and that one has already been handed to the engine: `reseat(from:)` takes
    /// it back. See ``PcmEngine/rearranged(_:isNow:)``.
    public func shuffleWhatIsComing() {
        guard let coming = QueueEdit.whatIsComing(count: queue.count, current: index) else {
            return
        }

        queue.replaceSubrange(coming, with: queue[coming].shuffled())

        // The playing record is at the same index as before: the shuffle did not touch it.
        reseat(from: index)
    }

    /// Whether there is anything a shuffle of what is coming could change.
    ///
    /// **A stated answer**, so the key that does this is on the screen only when it does
    /// something, and is not drawn all the time and quietly inert on the last record of
    /// a queue.
    public var canShuffleWhatIsComing: Bool {
        QueueEdit.whatIsComing(count: queue.count, current: index) != nil
    }

    /// Whether a record has already been handed to the engine to play next.
    ///
    /// Internal and not private so a test can ask it: it is the whole difference
    /// between a queue edit that reaches the sound and one that only reaches the
    /// screen, and from the outside the two look the same until the changeover.
    var loadedBehindTheNeedle: Bool { sound.hasSomethingNext }

    /// The gain that each source was handed to the engine with, front first. Internal so a
    /// test can check that the gain travels with the audio.
    var loudnessHandedOver: [SourceLoudness] { sound.loudnessComing }

    /// The list around the playing position has changed, and what is open belongs to
    /// positions that have moved.
    ///
    /// The track playing is kept (a song does not stop because the list around it was
    /// rearranged) and every other feed is closed, because each was opened for a
    /// running order that no longer exists. **The feeds are keyed by position**, so a
    /// queue edit makes every key but the current one wrong, and a map that is only half
    /// corrected is a player that says one track and plays another.
    ///
    /// **The engine is keyed by position too, so it must be told as well.** Closing a
    /// feed does not take back what the look-ahead already handed over: the next record
    /// is given to the engine a whole track early, so a queue rearranged at any point
    /// before the end of the current one would leave the old next record loaded behind
    /// the playing position. It would play, under the number that the list now gives
    /// to something else, so the app would name one track while another came out of the
    /// speaker. ``PcmEngine/rearranged(_:isNow:)`` is the message that takes it back.
    ///
    /// - Parameter wasAt: where the playing record stood **before** the edit, which is
    ///   the number that the feeds and the engine still know it by. Not the new one, and not
    ///   defaulted: reading `index` here would read the answer after the question has
    ///   changed.
    private func reseat(from wasAt: Int?) {
        guard let was = wasAt, let at = index else { return }

        // First, because the engine is the only one holding audio that is about to be heard.
        sound.rearranged(was, isNow: at)

        let playing = feeds[was]
        for (where_, feed) in feeds where where_ != was { feed.stop() }
        feeds = playing.map { [at: $0] } ?? [:]
        lookingAhead = nil

        let mine = generation
        Task { await lookAhead(after: at, generation: mine) }
    }

    /// Closes everything the queue had open. The station is not touched: it does not
    /// come through here.
    private func stopTheQueue() {
        sound.stop()
        for (_, feed) in feeds { feed.stop() }
        feeds = [:]
        lookingAhead = nil
    }

    /// The track that was playing was taken out of the queue.
    ///
    /// The generation moves **first**, for the reason `forget()` moves it first: a
    /// signature already in flight would otherwise arrive and start a track for a row
    /// that is no longer in the queue.
    private func stopBecauseItWentAway() {
        generation += 1

        stopTheQueue()

        position = .zero
        duration = .zero
        levelling = .none

        announce(nil)
    }

    // ── the speaker in another room ──

    /// Where the sound is going, or nil for the handset.
    public private(set) var castingTo: CastDevice? {
        didSet {
            guard oldValue?.id != castingTo?.id else { return }
            onCastChanged?(castingTo)
        }
    }

    /// Whether there is a cast session.
    ///
    /// **This is tied to `castingTo` on purpose.** The room's poll starts a few lines before
    /// `castingTo` is assigned, so reading `room.isOn` would make this true a little earlier
    /// and keep the poll's first answers. But this guard gates every action the room can
    /// cause, including bringing the sound home, so widening that window is not worth
    /// the risk. The stage still exists and still owns the watchdogs; it just does not
    /// answer this question.
    public var isCasting: Bool { castingTo != nil }

    /// Called whenever the sound moves between the handset and a room.
    ///
    /// **A cast ends in more places than it starts.** It is started in one place (the user
    /// picks a speaker) and ends in five: the room refusing, the room going away, stop being
    /// pressed, a failure, and coming home on purpose. Anything attached to the pair of
    /// calls would be left running by four of those. What would be left running is the
    /// hidden `MPVolumeView` that keeps the system's own volume display off the screen.
    /// See `VolumeKeys`.
    public var onCastChanged: ((CastDevice?) -> Void)?

    private var sink: CastSink?
    private var link: CastLink?
    private var castApp: ReceiverStatus.Application?

    /// What the other room is showing, for as long as there is another room.
    ///
    /// **Nil when not casting. It is the single route for everything a screen is told.**
    /// See ``RoomScreen``: whether the receiver is ours is answered inside it, so nothing
    /// here has to ask which one is running.
    private var screen: RoomScreen?

    /// Where a record's cover comes from. Handed in and not read here: the player
    /// does not know what a picture is. See ``RoomCover``.
    private let cover: RoomCover

    /// Sends what is playing to a speaker.
    ///
    /// **Nothing about the queue changes.** The engine keeps rendering, the record
    /// after this one is still opened before it is needed, and the only difference is
    /// that the handset stops being where the sound comes out. That is what a sink is.
    public func cast(to device: CastDevice) async throws {
        await stopCasting()

        // **The session begins here, not on the last line.** `watchTheRoom` starts
        // polling several lines before `castingTo` is assigned, and `theRoomSaid`
        // opens with a guard on whether there is a cast. Without this call, every answer
        // the room gave while it was being set up would be dropped, including the first
        // status after a LOAD, which is the one that says whether the receiver took it.
        room.pickingUp()

        // **The handset is stopped before the speaker is picked up, not during it.**
        //
        // Everything between here and `sink.begin` runs while the phone is still
        // rendering in real time, and it ends by tearing the render graph down and
        // building another one in its place. That caused a stutter at the exact moment
        // the user picked a speaker. The fix is not to make it fast but to make it
        // silent: audio that is not playing cannot under-run.
        //
        // ``PcmEngine/hush()`` and not `pause()`, because **nobody is asking
        // for silence here.** A player that was playing is still playing, in a room, a
        // second later, and the key over it never flickers. Nothing has to be carried
        // across and put back: moving the sound does not touch what the player is
        // doing, which is the whole purpose of `Playback`.
        sound.hush()

        let sink = CastSink(engine: sound)

        // **The room stopped taking the audio.** `RoomFeed` raises this when the
        // position the speaker reports stops moving while nothing is paused. This hook
        // keeps the player from staying on a stalled cast.
        // **Not a stop.** Nobody asked for silence; the destination stopped working. So
        // the sound comes home and carries on there, which is what `sink.Failed` does on
        // the desktop, while only `RemoteStopped` calls `Stop()`.
        sink.failed = { [weak self] why in
            Task { @MainActor in self?.act(on: .fellOver(why)) }
        }

        // **From where the playing position is, not from the top.** The engine's
        // destination moves under a record that is already playing, and the room carries on
        // from the same second the handset had reached.
        let url = try await sink.begin(from: position.seconds, named: device.name)

        let link = CastLink(to: device)

        do {
            let saying = try await link.open()

            // **Ours first, the stock one second**, which is what both C# heads do.
            //
            // RPM's own receiver is the only one that can talk back: a next pressed at
            // the speaker or spoken at it reaches the phone over its own namespace, and
            // the stock receiver does not know that namespace. A speaker that will
            // not launch ours plays perfectly well on the stock one, and loses that
            // button and nothing else.
            //
            // `RPM_STOCK_RECEIVER` forces the fallback, so the two can be
            // compared when a cast misbehaves.
            let wanted = ProcessInfo.processInfo.environment["RPM_STOCK_RECEIVER"] != nil
                       ? ReceiverStatus.defaultMediaReceiver : ReceiverStatus.rpmReceiver

            let app: ReceiverStatus.Application
            var ours = wanted != ReceiverStatus.defaultMediaReceiver

            do { app = try await link.launch(wanted) }
            catch {
                Self.log.notice("\(device.name, privacy: .public): stock receiver, \(error.localizedDescription, privacy: .public)")
                app = try await link.launch()
                ours = false
            }

            Self.log.notice("""
                \(device.name, privacy: .public): \(ours ? "RPM's receiver" : "the stock receiver", privacy: .public)                 on \(app.transportId, privacy: .public)
                """)

            // Only ours sends on it, so listening on the stock receiver would never hear
            // anything. It is off there, which also makes it clear which receiver is running.
            if ours { listenToTheRoom(saying) }

            // **Before it is told to fetch, not after.** Everything above happens in a
            // second or two, and a receiver that is handed a stream with nothing behind it
            // stutters until its own buffer catches up.
            //
            // Not waited for at all when the player is paused, because **a paused pump
            // fills nothing** and the wait would be its full six seconds, during a tap that
            // appears to have done nothing. The receiver buffers instead, which is the
            // accurate picture of a room that has been given a stream and no music yet.
            if !sound.isPaused { await sink.fill() }

            // **One stream for the whole queue**, not one per record. The stream has
            // no end, so a record ending is audio carrying on and not something the
            // receiver needs a new LOAD for, and a new LOAD would be an audible gap
            // between every two songs.
            //
            // What the screen shows is reported separately, and it has to be: a changeover
            // inside one stream has nothing to report on the media namespace, so a
            // television left to read this LOAD would show the record the queue started on
            // for the rest of the session. See ``RoomScreen``.
            let screen = RoomScreen(sink: sink, cover: cover,
                                    ours: ours ? (link, app.transportId) : nil)
            self.screen = screen

            // **Before the LOAD**, because the cover's address goes out inside it and a
            // receiver can ask for it before this side has opened a file.
            let art = await screen.showing(current, trackAt: position.seconds, loading: true)

            let loaded = try await link.load(
                CastMedia(url: url.absoluteString, contentType: "audio/wav",
                          title: current?.title ?? "", artist: current?.artist,
                          album: current?.album, artworkUrl: art),
                on: app.transportId)

            self.castApp = app

            // **Every transport message carries this**, and it is not the application
            // session: a PAUSE with the wrong one is refused and the key does nothing.
            // It is also what makes the room's words readable at all: see `RoomStream`.
            self.room.nowHolding(loaded.mediaSessionId)
            self.payWhatTheRoomIsOwed()

            // The first LOAD is held to the same promise as every later one: otherwise a
            // speaker that takes it and never starts would leave a cast that is silent for ever.
            holdTheRoomToIt(sink, named: device.name, generation: generation)

            // **How the level reaches the speaker.** Set here and not in the sink
            // because the link is the player's to hold, and the sink must not outlive
            // it: a level sent after the cast ends would change something else's volume.
            sink.turn = { [weak link] level in
                _ = try? await link?.setVolume(level)
            }

            // The room's own level, taken as the player's before anything is sent to
            // it. **The speaker's knob, not the handset's**: a room set to 20%
            // must not jump to whatever this phone happened to be at, and every
            // speaker plays its own blip when the level is set, so connecting must not
            // make a noise in another room.
            if let status = try? await link.status(), let level = status.volume?.level {
                roomVolume = Int((min(1, max(0, level)) * 100).rounded())
                _ = sink.roomMovedTo(level)
            }

            // **The speaker's own clock, from here on.** Nothing on this side knows
            // where the room has got to: what has been handed over is still in a
            // socket and in several seconds of the receiver's buffer. The playing
            // position, the pacing and the end of a track all read this clock.
            watchTheRoom(sink, on: link, at: app.transportId)
        } catch {
            // **What the stage was waiting on ends with the stage.** If this did not
            // run, `holdingTheRoomToIt` would keep going after a throw anywhere above:
            // the fetch watchdog would count its twenty seconds against a cast that no
            // longer exists, then report that a speaker nobody was casting to had failed
            // to fetch. Going through this one function makes that structural and
            // not a `cancel()` that somebody has to remember.
            leaveTheSitting(.gone)

            screen = nil
            await sink.end()
            await link.close()
            throw error
        }

        self.sink = sink
        self.link = link
        castingTo = device

        // A sleep timer waiting for the end of the track held the next record back on the
        // handset. With a speaker it is handed over: see `holdsBackTheNextRecord`.
        handOverOrHoldBackTheNextRecord()

        playbackChanged()
    }

    /// Asks the speaker where it has got to, four times a second, for as long as it
    /// is connected.
    ///
    /// A poll and not a subscription: a receiver pushes a status when something
    /// changes, and playing steadily is not a change. The desktop and the Uno head
    /// both poll.
    private func watchTheRoom(_ sink: CastSink, on link: CastLink, at transport: String) {
        watchingRoom?.cancel()

        watchingRoom = Task { [weak self] in
            var turns = 0
            var said = ""

            while !Task.isCancelled {
                // **Taken before the question, handed back with the answer.** A quarter
                // of a second is long enough for a thumb to change the track, and the
                // reply to a question asked before that arrives after it: it describes the
                // stream that was replaced, and what it says about it (nothing loaded)
                // is word for word what a stop at the speaker says. See `RoomStream`.
                // **Not a hop.** See `roomAtAGlance` for what a hop here would cost.
                let (asked, told, ours) = self?.roomAtAGlance.value ?? (-1, nil, nil)

                let report = await link.whereItIs(on: transport)

                // **Logged on every change, and once when it stops answering.** Fetching,
                // buffering, playing and having refused all look identical from this
                // side until the receiver says which it is, so without this a cast that
                // goes quiet leaves no evidence at all. It is a handful of
                // lines a minute: a room that is playing steadily says PLAYING once.
                let saying: String
                switch report {
                case .holding(let status): saying = "\(status.playerState) \(status.idleReason ?? "")"
                case .nothingLoaded: saying = "nothing loaded"
                case .noAnswer: saying = "no answer"
                }

                if saying != said {
                    said = saying
                    let at = if case .holding(let s) = report { s.currentTime ?? -1 } else { -1.0 }
                    Self.log.notice("""
                        the room says \(saying, privacy: .public)                         at \(at, format: .fixed(precision: 2), privacy: .public)s
                        """)
                }

                // The playing position: the only clock there is while casting, and only from
                // the stream that is actually on. A status about the one that was replaced
                // carries the second the *last* record had reached, and the position
                // only moves forward, so an answer arriving a moment late would drag the
                // new track's position to where the old one had got to.
                if case .holding(let heard) = report, heard.mediaSessionId == ours,
                   let at = heard.currentTime {
                    sink.says(at)
                }

                // **Handed over and not waited for.** Reading the report is the
                // main actor's business and the clock is not: `sink.says` has already
                // run above, off the actor, which is what keeps the room's clock
                // moving. Awaiting the delivery would put the whole poll back behind the main
                // actor: a search that holds it for half a minute would freeze the
                // clock, park the pump on a speaker that looks stuck, and bring the
                // sound home. The timing of this loop must not depend
                // on what a screen is doing.
                //
                // Late is fine and out of order is fine: `askedUnder` and `toldUnder` are
                // stamped before the question and are exactly what a stale answer is
                // dropped by.
                Task { @MainActor [weak self] in
                    self?.theRoomSaid(report, askedUnder: asked, toldUnder: told)
                }

                // The room's own knob, asked for less often than the position: it changes
                // when somebody touches it, and the position changes four times a second.
                //
                // **Stamped before it is asked, exactly as the transport question above
                // is.** This one carries the harder answer of the two: a receiver whose
                // media has just been taken away has nothing to do, and a Google speaker
                // does not stay in that state, it quits the application. If asked in that
                // window, the device answers truthfully that our session is gone, and
                // without the stamp that reads as somebody pressing stop in the room.
                turns += 1
                if turns % 4 == 0 {
                    // **Off the actor, like the question above it.** A single hop left in
                    // this loop stops the whole loop: the poll runs four times a
                    // second, and a main actor held for a search means thirty seconds of not
                    // running at all, which is a frozen position, a parked pump, and a
                    // session declared dead over a speaker that was playing fine.
                    let stamp = self?.roomAtAGlance.value.0 ?? -1

                    if let status = try? await link.status() {
                        Task { @MainActor [weak self] in
                            self?.theDeviceSaid(status, askedUnder: stamp)
                        }
                    }
                }

                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// The keys in the room: next and previous, pressed at the speaker or spoken at it.
    ///
    /// **Only RPM's own receiver sends these.** The stock one has no namespace for
    /// them, so a fallback cast never hears one, which is why nothing here has
    /// to know which receiver is running.
    private func listenToTheRoom(_ saying: AsyncStream<CastMessage>) {
        listeningToTheRoom?.cancel()

        listeningToTheRoom = Task { [weak self] in
            for await message in saying where message.namespace == CastLink.controlNamespace {
                guard let self else { return }

                // A bare shape is enough, because our own receiver is at both ends and
                // anything else on this namespace is a receiver newer than this app.
                if message.payload.contains(#""type":"next""#) {
                    await self.next()
                } else if message.payload.contains(#""type":"prev""#) {
                    await self.previous()
                } else if message.payload.contains(#""type":"artfail""#) {
                    // The receiver could not load the cover from the address it was
                    // given, and is asking for the picture itself. Ordinarily it already
                    // has it (the bytes go out with the record and do not wait to be
                    // asked), so this is the case where they had not been read yet when
                    // it tried.
                    await self.screen?.askedAgain()
                }
            }
        }
    }

    private var listeningToTheRoom: Task<Void, Never>?

    /// What the speaker says about itself, which is **the other half of the transport**.
    ///
    /// This follows the switch in `RPM.Core/Audio/CastSink.OnReceiverStatus`. While
    /// casting there is a second set of controls in the room (the speaker's own
    /// surface, the Google Home app, "Hey Google, pause"), and a player that does not
    /// follow them shows a pause key over a room that is playing.
    ///
    /// **The reading is not here.** It is in `RoomStream`, which holds the two facts that
    /// decide what the same words mean, and which can be tested without a speaker in the
    /// room.
    ///
    /// - Parameter askedUnder: what the room was holding when the question was asked.
    private func theRoomSaid(_ report: RoomReport, askedUnder: Int, toldUnder: Int?) {
        guard isCasting else { return }

        // The playing position changed, whatever else the report turns out to mean.
        if case .holding = report { playbackChanged() }

        // **Use the state machine's answer, not a fact scraped from the report.** See `RoomStream.reading`.
        act(on: room.reading(report, askedUnder: askedUnder, toldUnder: toldUnder,
                             against: sound.playback))
    }

    /// The device's own status, which is where a stop on a Google speaker actually shows
    /// up: it quits the receiver application and does not clear its media.
    ///
    /// - Parameter askedUnder: what the room was holding when the question was asked.
    private func theDeviceSaid(_ status: ReceiverStatus, askedUnder: Int) {
        // **Outside the guard**, because the knob is the device's own and is worth
        // following whatever the room is holding at the time.
        roomIsAt(status.volume?.level)

        guard isCasting, let app = castApp else { return }
        act(on: room.reading(status, ours: app.sessionId, askedUnder: askedUnder))
    }

    /// Does what the room asked.
    ///
    /// **There are two ways out of here, and they are different**, as
    /// `PlaybackService.cs` shows with two separate events:
    ///
    /// - Somebody asked for silence, so the session ends. `sink.RemoteStopped += () =>
    ///   Stop()`.
    /// - The speaker stopped being a working destination, so the music comes home and
    ///   carries on playing there. `sink.Failed += ... StopCasting()`.
    ///
    /// If the two were one, a network problem lasting thirty seconds would end the
    /// user's listening.
    private func act(on word: RoomStream.Word) {
        switch word {
        case .nothing:
            break

        case .pause:
            pause()

        case .resume:
            resume()

        case .stopped(let why):
            guard isCasting else { return }
            Self.log.error("""
                \(why.rawValue, privacy: .public); putting the music down \
                (\(String(describing: self.room.stage), privacy: .public), \
                room at \(self.sink?.heard ?? -1, format: .fixed(precision: 1), privacy: .public)s)
                """)
            stop()

            // The cast comes down after the queue because by now the speaker has already
            // ended the session at its end.
            Task { await stopCasting() }

        case .fellOver(let why):
            guard isCasting else { return }

            // **Logged at error level, with what the session was doing.** A cast coming
            // home on its own is the one thing a listener notices and cannot explain, and
            // this is the only record of why it happened.
            Self.log.error("""
                \(why, privacy: .public); bringing the sound home \
                (\(String(describing: self.room.stage), privacy: .public), \
                room at \(self.sink?.heard ?? -1, format: .fixed(precision: 1), privacy: .public)s, \
                \(self.sink?.waiting ?? -1, format: .fixed(precision: 1), privacy: .public)s in the ring)
                """)

            // **Not `stop`.** Nobody asked for silence. `stopCasting` puts the playing position
            // back where the room had got to, and the record carries on out of the handset.
            Task { await stopCasting() }
        }
    }

    /// The room's own level, adopted and not argued with.
    private func roomIsAt(_ level: Double?) {
        guard let moved = sink?.roomMovedTo(level) else { return }

        roomVolume = moved
        playbackChanged()
    }

    /// Where the speaker's knob is, 0 to 100, as far as this side knows.
    ///
    /// **This is the number a volume key steps from, and it is deliberately not the
    /// handset's**: the handset's is what the phone would play at, and until the room has
    /// answered the two numbers differ. Stepping from the wrong one makes the first press
    /// jump a quiet room to full.
    public private(set) var roomVolume: Int = 100

    private var watchingRoom: Task<Void, Never>?

    /// Takes our stream off the room, and returns the address of the next one.
    ///
    /// **The single entry point.** The cast faults came from doing its two halves
    /// apart. Cutting the connection stops the old reader and the new track from
    /// taking turns on the same ring, a piece each. Forgetting the session in
    /// the same call stops the poll from reading the silence that follows as a
    /// hand on the speaker. Neither is optional and neither is first.
    ///
    /// The address is minted here and loaded later, which is the right way round: the
    /// server answers for the new name from this moment, so a receiver still holding the
    /// old one is refused and is not handed the next song on the end of the last one.
    private func takeTheRoomsStream() async -> URL? {
        room.takenBack()
        return await sink?.handOver()
    }

    /// The record at the playing position changed while a speaker was connected, so the room
    /// is given a new stream and told to fetch it.
    ///
    /// Nothing happens when the sound is on the handset, which is the ordinary case: the
    /// whole of this is one `guard` through an afternoon of listening with no speaker.
    ///
    /// **The playing position's own second, not zero.** A seek is a changeover too, and the
    /// stream it starts begins where the listener put the position.
    ///
    /// - Parameter mine: the claim this changeover is made under. **Checked after
    ///   the wait as well as before it**, and its safety depends on that. Filling
    ///   the ring takes as long as it takes, and a thumb fits inside that time: two skips in a
    ///   row put two of these in flight, each having minted a name, and if the older one's
    ///   LOAD landed second, the receiver would be fetching an address the server
    ///   has already stopped answering. The result is silence, until something else changed
    ///   the track.
    private func handTheRoomTheNewTrack(_ address: URL?, generation mine: Int) async {
        guard let address else { return }
        guard mine == generation else { return }
        guard let sink, let link, let app = castApp else { return }

        // **A head start, and it is quick because nothing is draining the ring.**
        //
        // A receiver will not begin until it has buffered a few seconds, and audio
        // rendered in real time can never catch up: what is waiting when it connects is
        // all it will ever have. Handed a thin ring, it stutters through the first
        // seconds of every skip.
        //
        // The wait can take its full six seconds if the old connection is still
        // pulling the ring empty as fast as the pump fills it. That is the same fault
        // as the fragments. With the room released first, the ring fills at decode speed
        // and this returns almost at once.
        await sink.fill()

        // Somebody moved on while it filled. The name this minted is already stale;
        // whoever holds the generation now has minted their own and will load it.
        // **Nothing is said to the room here**: the room is holding nothing of ours and
        // the live changeover is about to say what it is holding instead.
        guard mine == generation else { return }

        // **Before the LOAD**, and the screen is told that the clock starts again: a LOAD
        // sets the receiver's own clock back to zero, so the anchor the screen runs its
        // running time from is zero in the stream and wherever the playing position was
        // put in the record.
        let art = await screen?.showing(current, trackAt: position.seconds, loading: true)

        let loaded: MediaStatus
        do {
            loaded = try await link.load(
                CastMedia(url: address.absoluteString, contentType: "audio/wav",
                          title: current?.title ?? "", artist: current?.artist,
                          album: current?.album, artworkUrl: art),
                on: app.transportId)
        } catch {
            // **The generation is checked again here, and this line is essential.** A LOAD
            // is a round trip to a speaker and a thumb fits inside one, so a second press
            // puts a second changeover in flight while this one is still
            // waiting for its answer, and the answer the receiver gives the overtaken one
            // is a refusal. Taken at face value, that refusal would bring the music home, out
            // of a room that at that very moment is starting the track that was actually
            // asked for. Whoever holds the generation speaks. The one that lost it says
            // nothing at all, in this failure branch exactly as in the three guards above it.
            guard mine == generation else { return }

            // The protocol also says it: `LOAD_CANCELLED` **is** the receiver saying it was
            // overtaken. See ``CastLink/Rejected/superseded``. This covers the case where
            // the two checks do not agree.
            if let rejected = error as? CastLink.Rejected, rejected == .superseded { return }

            // **The speaker would not take it**, so it is not a destination any more: it
            // is holding nothing and nothing is going to arrive. The music comes home
            // and does not play on into a room that has been silent since the cut.
            act(on: .fellOver("the room would not take the new track"))
            return
        }

        // The same check on the way out of the success branch, for the opposite half
        // of the same fault: a LOAD that lands late and *worked* would otherwise write its
        // own media session over the one the live changeover has just put there. The room
        // would then play perfectly while every status it sends is filtered
        // out as somebody else's, so the position never moves and the track never ends.
        guard mine == generation else { return }

        // **Every transport message carries this**, and it is what makes the room's next
        // words readable: until it is set, everything the room says is about the stream
        // that was taken away.
        room.nowHolding(loaded.mediaSessionId)
        payWhatTheRoomIsOwed()

        // Taking a LOAD is not fetching the stream. See ``holdTheRoomToIt(_:named:generation:)``.
        holdTheRoomToIt(sink, named: castingTo?.name ?? link.name, generation: mine)
    }

    /// Twenty seconds, the same as the desktop's `CastSink.FetchTimeout`, for the same reason:
    /// long enough for a speaker on a busy network to respond, short enough that
    /// the user is not left looking at a room that is never going to make a sound.
    private static let fetchWithin: Duration = .seconds(20)

    /// Holds the receiver to a LOAD it has taken.
    ///
    /// **Taking a LOAD is not fetching the stream**, and the gap between the two is a
    /// failure that nothing else on this side can see. A receiver answers the LOAD with a media
    /// session and then, on a speaker that has quietly left the network, never opens the
    /// connection at all. With no position ever reported, the pacer falls back to the ring,
    /// which is the one state its stall watch does not run in: the pump parks on a full
    /// ring and the room stays silent for as long as somebody is willing to wait, with nothing
    /// raised anywhere. The desktop's `RPM.Core/Audio/CastSink.LoadAsync` has the same watch.
    ///
    /// - Parameter mine: the changeover this watch belongs to. A watch may only speak
    ///   for the LOAD that started it, so a skip landing inside the twenty seconds
    ///   cancels this one and starts its own, and does not fail the cast it replaced.
    private func holdTheRoomToIt(_ sink: CastSink, named: String, generation mine: Int) {
        holdingTheRoomToIt?.cancel()

        holdingTheRoomToIt = Task { [weak self] in
            let until = ContinuousClock.now.advanced(by: Self.fetchWithin)

            while ContinuousClock.now < until {
                if Task.isCancelled { return }
                if await sink.wasFetched() {
                    // **It came.** Leaving `holding` is what retires this watch, so the
                    // stage reports what is true and the task does not just return quietly.
                    await MainActor.run { self?.room.itFetched() }
                    return
                }

                try? await Task.sleep(for: .milliseconds(250))
            }

            guard !Task.isCancelled, let self, mine == self.generation, self.isCasting
            else { return }

            self.act(on: .fellOver("\(named) never fetched the stream."))
        }
    }

    private var holdingTheRoomToIt: Task<Void, Never>?

    /// Sends the key that was pressed while the room had no session to send it under.
    ///
    /// Called wherever a session is taken, which is the only place it can be paid.
    private func payWhatTheRoomIsOwed() {
        guard let owed = room.settleUp() else { return }

        Self.log.notice("paying the room what it is owed: \(owed ? "play" : "pause", privacy: .public)")
        tellTheRoom(playing: owed)
    }

    /// Ends the session and everything that was waiting on a stage of it.
    ///
    /// **The single way out.** Three tasks are started, each at its own line. Each must be
    /// cancelled, and cancelling them one by one at each exit risks missing one. What a
    /// stage is waiting on is listed with the stage in `RoomStream.Stage`, and leaving
    /// ends it.
    private func leaveTheSitting(_ how: RoomStream.Stage) {
        watchingRoom?.cancel();        watchingRoom = nil
        listeningToTheRoom?.cancel();  listeningToTheRoom = nil
        holdingTheRoomToIt?.cancel();  holdingTheRoomToIt = nil

        if case .gone = how { room.gone() }
    }

    /// Brings the sound back to the handset.
    public func stopCasting() async {
        // **Before the sink goes.** A watch left running would read a torn-down server
        // as a receiver that never fetched, and fail a cast that has already ended.
        // On the way into a *second* speaker, that would be a fresh cast brought home by the
        // last one's stopwatch. All three go together; see ``leaveTheSitting(_:)``.
        leaveTheSitting(.gone)
        await stopCastingRest()
    }

    private func stopCastingRest() async {
        watchingRoom?.cancel()
        watchingRoom = nil

        listeningToTheRoom?.cancel()
        listeningToTheRoom = nil

        // **Before the link closes**, so that anything still in flight for it is dropped
        // and not sent to a socket that is going away. Nothing is said to the receiver on
        // the way out: the application is about to be stopped, and a screen told what is
        // playing while it is being taken down would get a message about a room that has ended.
        screen = nil

        // **Before the sink goes.** A watch left running would read a torn-down server as
        // a receiver that never fetched, and fail a cast that has already ended. On
        // the way into a *second* speaker, that would be a fresh cast brought home by the
        // last one's stopwatch.
        holdingTheRoomToIt?.cancel()
        holdingTheRoomToIt = nil

        // Where the **room** had got to, which is not where this side had got to: the
        // decoder is allowed to run up to eight seconds ahead of the speaker, and that
        // is exactly how far the sound would jump forward on coming home if the playing
        // position were simply left where it stood.
        let wasAt = sink?.heard

        if let link {
            if let app = castApp { try? await link.stop(app.sessionId) }
            await link.close()
        }
        await sink?.end()

        sink = nil
        link = nil
        castApp = nil
        castingTo = nil
        room.gone()

        // **Put back where the room was.** A station cannot be moved through and does
        // not need to be: it has no position to come back to and its bytes carry on
        // arriving. A record does have one, and asking for it again from the right byte
        // makes the join sound like a join and not like a skip.
        // If there is nothing to put back, the session ended with the room, which is
        // what a stop at the speaker does. That case is handled by this condition and not
        // by a seek that would fail and log that it could not be done.
        if let wasAt, !onTheRadio, index != nil {
            let landed = seek(to: .seconds(wasAt))
            Self.log.notice("""
                home: the room was at \(wasAt, format: .fixed(precision: 2), privacy: .public)s,                 \(landed.map { "landed at \($0)" } ?? "could not be moved there", privacy: .public)
                """)
        }

        playbackChanged()
    }

    /// Moves the speaker's own knob, 0 to 100.
    ///
    /// Coalesced and rate limited by ``CastVolume``: a finger held on a volume key
    /// produces changes much faster than a speaker can answer them.
    public func setRoomVolume(step: Int) {
        roomVolume = min(100, max(0, step))
        sink?.turnTheRoom(to: roomVolume)
        playbackChanged()
    }

    // ── what draws the music ──

    /// The sound as it is being played, for whatever is drawing it.
    ///
    /// **Nil until somebody asks.** A tap is running work, and a phone pays for running
    /// work in heat whether or not the screen shows the result. So the stage takes it when
    /// it comes up and gives it back when it goes down, which is the same contract as the
    /// Uno head's stage.
    ///
    /// It hears the handset, so it hears nothing while casting: there is no local graph
    /// then. That is the correct answer and not a gap, because what a visualiser
    /// draws is what this phone is playing.
    public private(set) var drawing: RoomSound?

    /// Starts or stops handing the played sound to whatever is drawing it.
    public func draw(_ on: Bool) {
        // **Nothing is attached or removed here.** The engine's own timeline is
        // written by the pump whether or not anybody is looking, which costs a mono fold
        // of one block five times a second and gives an answer that cannot be out of step
        // with the sound. This only records whether there is a reader. A reader
        // that walks away without saying so leaves a task behind, not a tap.
        drawing = on ? sound.played : nil
    }

    /// The room's volume, zero to one. Not the track's: this changes the speaker
    /// itself, and somebody standing next to it hears the change without the phone.
    public func setRoomVolume(_ level: Double) async {
        _ = try? await link?.setVolume(level)
    }

    // ── the engine ──

    private func watchTheEngine() {
        // **The engine says when the track being HEARD changes**, which is not when
        // the next one was handed over: gapless means both are in the node at once,
        // and only the node's clock knows which of them is coming out of the speaker.
        // This is the only writer of `index`.
        sound.moved = { [weak self] at in
            Task { @MainActor in self?.settleFromTheEngine(at) }
        }

        sound.ranOut = { [weak self] ending in
            Task { @MainActor in self?.queueRanOut(ending) }
        }

        // A station is somebody else's stream and keeps AVFoundation's own reporting.
        watching.append(radio.observe(\.timeControlStatus, options: [.new]) { [weak self] radio, _ in
            let standing = radio.timeControlStatus

            Task { @MainActor in
                guard let self, self.onTheRadio else { return }

                self.isPlaying = standing == .playing
                self.opening = standing == .waitingToPlayAtSpecifiedRate
                self.playbackChanged()
                self.noteTheFirstSound(standing == .playing)
            }
        })

        // Four times a second is enough for a progress bar and cheap enough to leave
        // running: anything faster redraws a line that nobody can see move. The engine
        // has no callback for the playing position and should not have one: it would be a
        // hop per buffer, fifty times a second, to move a line by three pixels.
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Reads the engine, once every quarter of a second.
    private func tick() {
        // The radio, before anything that returns early: an HLS station is on AVFoundation, and
        // its `isPlaying` is kept by the observer and not read here, but it is heard all the
        // same. A reading that is behind by one tick on the engine path is a quarter of a second.
        if let heard = stationsHeard.read(station: station, playing: isPlaying) {
            onStationHeard?(heard)
        }

        guard !onAvFoundation else { return }

        let was = (isPlaying, opening)

        // A station has no position and no length: it does not end, and a seek bar
        // reads zero as nothing to scrub. Everything else about it is the engine's
        // answer, the same as a record's.
        guard !onTheRadio else {
            isPlaying = sound.isPlaying && !sound.starved
            opening = engineIsOpening
            tellTheLockScreen(if: was)
            return
        }

        position = .seconds(sound.position)
        isPlaying = sound.isPlaying && !sound.starved

        // What has been listened to, read off the same tick as everything else. It is synchronous
        // and in order: the tally sums stretches across seeks, and readings that arrived out of
        // order would score the wrong one. What comes out is handed on; writing it down is the caller's job.
        if let counted = plays.read(track: current, session: playSession,
                                    position: position.seconds, duration: duration.seconds) {
            onPlayCounted?(counted)
        }

        // **Buffering is a fact here and not a guess.** Either the node is running
        // and everything handed to it has been played, or it has not been started
        // because there is not yet enough to start on. Both are the correct answer to
        // why nothing is coming out.
        opening = engineIsOpening

        tellTheLockScreen(if: was)
        noteTheFirstSound(isPlaying)
    }

    /// Whether the engine is waiting for enough to start on, or has run dry.
    ///
    /// **Not while paused.** A record put on under a pause (a seek while paused, or the
    /// sleep timer leaving the next record ready) is never started, so the engine reports
    /// it as priming for as long as it stays paused. Read directly, that would put a spinner
    /// on the play key over a paused player.
    private var engineIsOpening: Bool {
        sound.starved || (sound.priming && !sound.isPaused)
    }

    /// Reports when the engine has started, stopped, run dry or filled again.
    ///
    /// **On the change and not on the tick.** The elapsed time does not need to be reported
    /// four times a second, because iOS runs the clock itself from the rate it was last
    /// given. The rate does need to be reported when it changes: a record that starved and
    /// came back would otherwise draw the same key throughout.
    private func tellTheLockScreen(if was: (Bool, Bool)) {
        // **Before the guard**, because the two are not the same question: the engine
        // can move from priming to playing, or be started by a seek, without either of
        // the figures below changing. The key draws ``loaded``, so ``loaded`` is read
        // on every tick and the lock screen is told only when it has something to hear.
        readTheEngine()

        guard (isPlaying, opening) != was else { return }
        onPlaybackChanged?()
    }

    /// Logs how long the tap took to become sound, once per start.
    private func noteTheFirstSound(_ playing: Bool) {
        guard playing, let asked = awaited else { return }

        awaited = nil
        Self.log.notice(
            "first sound in \(Date().timeIntervalSince(asked), format: .fixed(precision: 3))s")
    }

    /// The engine has moved into the next record.
    private func settleFromTheEngine(_ at: Int) {
        guard !onTheRadio, queue.indices.contains(at) else { return }

        // The engine went on into the next record by itself, as against arriving where a
        // start already put the playing position: every start settles before the engine
        // hears it.
        let wentOnByItself = index.map { $0 + 1 == at } ?? false

        settle(on: at)

        // **The sleep timer's other way of ending a track.** Reached when the next record
        // was handed over anyway: while casting (see `holdsBackTheNextRecord`), or when
        // the timer was set so close to the end that the pump had already moved on to the
        // next one. The next record has just begun, and it is paused where it stands.
        var timer = sleepTimer
        if wentOnByItself, timer.trackEnded() {
            sleepTimer = timer
            pause()
        }

        // **The changeover inside one stream, which is the only place anything reports it.**
        // The media on the receiver has not changed and is not going to: the record after
        // this one is the same endless stream carrying on, so there is no LOAD to carry
        // the new record's name and nothing else tells the room. If this were left out, a
        // television would show the record the queue started on until somebody pressed a key.
        //
        // **On time and not early.** `PcmEngine.playing` reads the speaker's own
        // reported position while casting, so this fires when the room reaches the new
        // record and not when the pump wrote it. That is why the anchor is where the
        // room is now, and why the desktop's answer to the same question is different:
        // its `TrackChanged` runs at the pump and has to anchor the announcement ahead
        // of the audio.
        if let screen, isCasting {
            let streamAt = sink?.inTheStream ?? 0
            let record = current
            Task { await screen.showing(record, trackAt: 0, streamAt: streamAt) }
        }

        // The record after the one that just started, so it is ready before it is
        // needed and not when it is.
        let mine = generation
        Task { await lookAhead(after: at, generation: mine) }
    }

    /// Watches a **station's** buffer, to show it on screen.
    ///
    /// **It does not restart anything.** AVFoundation waits and resumes on its own,
    /// and a second `play()` on top of that does nothing or conflicts with it. What
    /// is left for this to do is the spinner: a station that has run dry looks exactly
    /// like a station that is playing quietly, unless something reports it. The
    /// queue does not come through here: its engine waits by itself and reports this
    /// through `starved`.
    private func watchTheBuffer(of item: AVPlayerItem) {
        watchingBuffer = []

        watchingBuffer.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
            [weak self] item, _ in
            let ready = item.isPlaybackLikelyToKeepUp
            Task { @MainActor in self?.filledUp(ready) }
        })

        stalled.map(NotificationCenter.default.removeObserver)
        stalled = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: item, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.ranDry() }
        }
    }

    /// The station ran dry. This is not an error and not the end of anything.
    private func ranDry() {
        recovering = true
        opening = true
        playbackChanged()
    }

    /// Enough has arrived to go on with. Acts only after a stall that this player saw: this
    /// fires on every ordinary fill as well, and a station that somebody had paused would
    /// otherwise start again by itself.
    private func filledUp(_ ready: Bool) {
        guard ready, recovering else { return }

        recovering = false
        opening = false
        playbackChanged()
    }

    /// Everything handed to the engine has been played.
    ///
    /// Internal and not private so a test can call this without an audio
    /// engine: what it decides (carry on, try again, or stop) is the
    /// difference between a queue that ends and one that dies, and neither is
    /// reachable from the outside otherwise. Nothing but the engine calls it.
    func queueRanOut(_ ending: Ending) {
        guard !onTheRadio else { return }

        Self.log.notice("""
            the record stopped at \(self.position.seconds, format: .fixed(precision: 1))s \
            of \(self.duration.seconds, format: .fixed(precision: 1))s: \
            \(ending.said, privacy: .public)
            """)

        // **The one ordinary ending, and it is stated explicitly.** Do not work it out
        // by comparing how far the playing position had got against the length in the
        // track's tags. That comparison cannot tell a record that stopped from a record
        // that is short: a stream the store refused after three seconds would read as a
        // song that had finished, and the queue would move on to the next one. Instead
        // the answer is the file's own header compared with what the decoder actually made
        // of it, reported by the source that knows. See ``Ending``.
        guard !ending.reachedItsEnd else {
            // Either the record ended, or the look-ahead was not ready in time, or the
            // sleep timer held it back. There is a next track and it is started the slow
            // way: a gap, not a stop.
            if hasNext, let at = index {
                carryOn(after: at)
                return
            }

            // Nothing behind it, and it reached its end: the queue is done, which is the
            // same ending as the stop key and gets the same answer. A player left
            // standing over a finished record keeps a strip at the foot of every screen,
            // an entry on the lock screen and a queue, none of which has anything left
            // to do.
            stop()
            return
        }

        say(ending)

        // A record from a computer on the home network that stopped part way: the computer is
        // reported, and the record starts over from the cloud at the same place instead of
        // being requested from the same address again.
        if ending.worthAnotherGo, let at = index, let near = nearbyFeeds.removeValue(forKey: at) {
            nearby.failed(near)
            let got = position
            Task { await self.startOverFromTheCloud(at: at, from: got) }
            return
        }

        // **Reported while it happens and not only after the attempts have run out.** A
        // player that goes quiet for three attempts and then admits it gave up tells
        // the listener nothing for the whole time they were wondering. The sentence
        // for each failure worth repeating already says that it is trying again.
        if ending.worthAnotherGo, let at = index, queue.indices.contains(at),
           retries.mayRetry(queue[at].rpmId) {

            // From where it stopped. **A downloaded stream's seek already does this**: the
            // same record asked for again from another byte, which is exactly what
            // reopening means here.
            if seek(to: position) != nil {
                playbackChanged()
                return
            }
        }

        // It stopped, and there is nothing left to try. An album is not a wall that
        // the user has to press stop to get past, so the queue carries on, with the reason for
        // the gap left on the screen behind it.
        if hasNext, let at = index {
            carryOn(after: at)
            return
        }

        // **The last record stopped and did not end, and has no attempts left.** It has
        // something to say about why and nowhere else to say it, so the player is left
        // standing exactly as it is: clearing the queue here would take the message off
        // the screen along with the record it is about.
        isPlaying = false
        opening = false
        playbackChanged()
    }

    /// Opens the record at `at` again, this time skipping the computer that failed, and moves the
    /// playing position back to where it had got. Only on the same record: a start that
    /// stepped on lands at the top of the next one.
    private func startOverFromTheCloud(at: Int, from got: Duration) async {
        feeds[at]?.stop()
        feeds[at] = nil
        await startPlaying(queue, from: at, because: .carryOnAsBefore, list: .theQueue, arriving: .plays)
        if got > .zero, index == at { _ = seek(to: got) }
    }

    /// Puts the reason on the screen.
    private func say(_ ending: Ending) {
        failure = ending.failure(heard: position.seconds)
        trouble = failure.said
    }

    /// Sets what is playing. **Called more than once for the same track** (when it is
    /// tapped, when its address comes back, and when the engine reaches it), so
    /// everything here is safe to set again and the announcement is not repeated.
    private func settle(on at: Int) {
        index = at

        // The session reaches back to wherever the playing position has actually been. Pressing
        // back at the track it started on plays the one above, and that one is then
        // part of the session and is not something that was skipped.
        earliest = min(earliest, at)

        position = .zero
        duration = queue.indices.contains(at) ? queue[at].duration : .zero

        // Taken from the signature this item was built from and not from `kilobits`,
        // which is what was ASKED for. The two differ whenever the store has no
        // rendition at the asked rate, and the line is only useful if it can
        // be trusted.
        playingKilobits = queue.indices.contains(at)
            ? copies.copy(of: queue[at].rpmId)?.kilobits
                ?? urls.known(queue[at].rpmId, rate: kilobits)?.kilobits
            : nil

        // What is reported about the level. The gain itself travels with the source into
        // the engine (see `loudness(of:)`), because the engine reaches the next track on
        // its own clock and a gain set from here would land after the first block of it.
        levelling = level(queue.indices.contains(at) ? queue[at] : nil)

        announce(current)
    }

    // ── the two hops ──

    /// The look-ahead, started when a track becomes current and not when it ends,
    /// so it has a whole track's worth of time to sign an address and open a file.
    private func lookAhead(after at: Int, generation mine: Int) async {
        let next = at + 1
        guard queue.indices.contains(next), lookingAhead != next else { return }

        // Offline, a record with no copy here cannot be opened, and trying would put the
        // offline sentence over the record that is playing perfectly well from the
        // phone. The queue steps over it when this one ends: a gap, not a stop.
        guard reach.now.isOnline || copies.copy(of: queue[next].rpmId) != nil else { return }

        // The sleep timer waits for this track to end: nothing goes behind it, so the
        // engine runs out when it ends and `queueRanOut` pauses there. Nothing is opened
        // either; the record is opened when the queue moves on to it.
        guard !holdsBackTheNextRecord else { return }

        lookingAhead = next

        // Taken with the track the feed is opened for. If a row below the playing position is
        // removed during the open, `index` stays as it was and `queue[next]` is past the end.
        // The setting is not part of this: the engine reads it live.
        let loud = loudness(of: queue[next])

        guard let feed = await open(at: next, generation: mine) else { return }
        guard mine == generation, index == at else { feed.stop(); return }

        // Checked again after the await: the timer can be set while the record opens. The
        // feed stays where it is, and a later look-ahead or start takes it from there.
        guard !holdsBackTheNextRecord else { lookingAhead = nil; return }

        sound.queue(feed.pcm, id: next, loudness: loud)
    }

    /// Signs a track's address, starts downloading it, and waits for enough of it to know
    /// what it is.
    ///
    /// **Enough is the header, not the file.** A few kilobytes give the format, and
    /// everything after that arrives behind the music. What this waits for is the
    /// decoder saying it can decode, which is the first moment there is anything to
    /// hand the engine.
    ///
    /// A feed already open for this position is handed back and not opened again:
    /// the purpose of the look-ahead is that pressing next finds the network work
    /// already done.
    ///
    /// - Parameter mine: the claim this open is made under. **Checked while it
    ///   waits, not only when it finishes.** A record that is skipped past would otherwise
    ///   go on downloading for as long as it took to produce a format (twenty seconds on the
    ///   sort of connection where it matters) and be thrown away when it got there.
    ///   This is the part of `StartGate` that stops the loser: the point of a claim is that
    ///   the loser stops.
    private func open(at: Int, generation mine: Int) async -> TrackFeed? {
        guard queue.indices.contains(at) else { return nil }

        if let already = feeds[at], already.pcm.ready, already.trouble == nil {
            return already
        }

        let track = queue[at]

        // **The copy on the phone first, and nothing is signed for it.** This is what
        // makes a downloaded record play with no network at all.
        if let copy = copies.copy(of: track.rpmId) {
            feeds[at]?.stop()
            let feed = TrackFeed()
            feeds[at] = feed
            feed.start(file: copy.file)
            return await ready(feed, at: at, generation: mine)
        }

        // **A computer on the home network next**, while it is there. A feed that will not start
        // from it is reported and the track is signed from the cloud below, so the computer
        // going away costs a pause and not the track.
        nearbyFeeds[at] = nil
        if let near = await nearby.address(of: track, on: shelves.shelf(of: track.rpmId)) {
            guard mine == generation else { return nil }

            feeds[at]?.stop()
            let feed = TrackFeed()
            feeds[at] = feed
            failure = .none
            feed.start(near, kind: .stored)

            if let started = await ready(feed, at: at, generation: mine) {
                nearbyFeeds[at] = near
                return started
            }
            guard mine == generation else { return nil }
            nearby.failed(near)
        }

        guard let signed = await sign(track) else {
            // Nothing is shown on the screen for a start that was abandoned on purpose: a
            // record tapped while another was still signing is not a fault, and a red
            // sentence about it would blame the user for changing their mind.
            trouble = failure.said
            return nil
        }

        // Signed, and in the meantime somebody moved on. **The cheapest download to
        // stop is the one that never started**, so nothing is opened at all, and the slot
        // is left exactly as whoever holds the claim now has it.
        guard mine == generation else { return nil }

        feeds[at]?.stop()
        let feed = TrackFeed()
        feeds[at] = feed
        feed.start(signed.url, kind: signed.kind)

        return await ready(feed, at: at, generation: mine)
    }

    /// Waits for a feed to have a header, or gives it up.
    private func ready(_ feed: TrackFeed, at: Int, generation mine: Int) async -> TrackFeed? {
        // Twenty seconds (800 polls of 25 ms). After that the connection is not slow, it is
        // not going to answer, and the sentence for it is already written.
        for _ in 0..<800 {
            if feed.pcm.ready { trouble = nil; return feed }

            // Somebody moved on. Nothing is shown on the screen and nothing is
            // remembered: this is not a fault, it is a record nobody wants any more.
            guard mine == generation else {
                feed.stop()
                letGo(feed, at: at)
                return nil
            }

            if let why = feed.trouble {
                failure = why == .refused(403) ? .signedIn : .store
                trouble = failure.said
                letGo(feed, at: at)
                return nil
            }

            try? await Task.sleep(for: .milliseconds(25))
        }

        failure = .timeout
        trouble = failure.said
        feed.stop()
        letGo(feed, at: at)
        return nil
    }

    /// Forgets a feed, **and only if it is still the one being forgotten.**
    ///
    /// This runs after an `await`, and by then another start may have put its own feed
    /// at the same place: two taps on the same row, or a look-ahead overtaken by the
    /// tap that replaced it. Clearing the slot blindly would take the live record's bytes
    /// away from it, and the symptom is a track that silently never starts.
    private func letGo(_ feed: TrackFeed, at: Int) {
        if feeds[at] === feed { feeds[at] = nil }
    }

    /// A signed address, from this session's own copy where it is still valid.
    ///
    /// Never from one held since the queue was made: the store's signature expires,
    /// and a queue left paused overnight is a queue of dead addresses.
    private func sign(_ track: CloudTrack) async -> StreamUrlCache.Signed? {
        if let known = urls.known(track.rpmId, rate: kilobits) { failure = .none; return known }

        do {
            let said = try await source.stream(shelves.shelf(of: track.rpmId),
                                               rpmId: track.rpmId, kilobits: kilobits)
            let signed = StreamUrlCache.Signed(
                url: said.url, kilobits: said.kilobits, kind: said.kind)
            urls.note(track.rpmId, asked: kilobits, signed: signed)
            failure = .none
            return signed
        } catch {
            failure = PlaybackFailure.read(error)
            return nil
        }
    }

    // ── how loud ──

    func level(_ track: CloudTrack?) -> NormalizeDecision {
        guard let track else { return .none }
        return loudness(of: track).gain(under: normalize)
    }

    /// What a track is levelled from, as the queue stands now. Handed to the engine with
    /// the track's audio.
    ///
    /// Album gain in album order, track gain on shuffle. The queue knows which it is: a
    /// record played as a record is its own tracks in their own order.
    func loudness(of track: CloudTrack) -> SourceLoudness {
        SourceLoudness(track: Level(track.tags), album: albumLevel,
                       inAlbumOrder: playingARecord, albumIsClassical: classical(track))
    }

    /// Whether what is in the queue is a record and not a set of songs. Derived
    /// from the queue itself and not remembered from how it was started, so it is
    /// still correct after a track is removed.
    var playingARecord: Bool { queueIsARecord }

    /// The record's own loudness, from the tracks in hand. Nothing measures a whole
    /// album on a phone; this is the same weighted mean the desktop computes.
    var albumLevel: Level { levelOfTheRecord }

    private var queueIsARecord = true
    private var levelOfTheRecord: Level = .unknown

    /// Works out both of those, **when the queue changes and not when a track
    /// does**.
    ///
    /// Each is a walk of the whole queue. Repeating the walk for every track that
    /// comes round would run it on the main actor in the middle of a start. On a
    /// record that is twelve rows and nobody would notice; on a whole library shuffled
    /// it is every song the user owns, twice, between one track and the next.
    ///
    /// Still derived from the queue and not remembered from how it was started,
    /// which keeps it correct after a row is taken out of it: the queue is the
    /// only thing that has to change for this to be worked out again.
    private func relevelTheQueue() {
        queueIsARecord = queue.count > 1 ? Set(queue.map { $0.album ?? "" }).count == 1 : true

        guard queueIsARecord else { levelOfTheRecord = .unknown; return }

        let readings = queue.compactMap { track -> (lufs: Double, seconds: Double)? in
            guard let tags = track.tags, tags.hasLoudness else { return nil }
            return (lufs: tags.loudnessLufs, seconds: tags.durationSeconds)
        }
        guard !readings.isEmpty else { levelOfTheRecord = .unknown; return }

        let peak = queue.compactMap { $0.tags?.truePeak }.filter { $0 > 0 }.max()
        levelOfTheRecord = Level(lufs: ReplayGain.albumLufs(readings), truePeak: peak)
    }

    /// Lets the engine go.
    ///
    /// Not in `deinit`: the periodic observer's token has to be handed back on the
    /// main actor, and a `deinit` runs wherever the last reference happens to be
    /// dropped. A player that is never released does not need this; one that is
    /// replaced does.
    public func close() {
        ticking?.cancel()
        ticking = nil
        watching = []
        watchingBuffer = []
        stalled.map(NotificationCenter.default.removeObserver)
        stalled = nil

        stopTheQueue()
        radio.pause()
        radio.removeAllItems()
    }
}

extension Duration {
    /// The whole thing as a `Double`, for the frameworks that only accept one:
    /// `CMTime`, the lock screen, and a progress bar's width.
    ///
    /// Public because every view that draws a clock needs it. It does not clash with
    /// `Duration.seconds(_:)`: that one is a factory on the type,
    /// this one is a reading of a value.
    public var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

extension TrackShelves: ShelfSource {}

/// Carries what a station announces off the metadata queue and into a closure.
///
/// Its own class because `AVPlayerItemMetadataOutput` needs a delegate object and the
/// player is a main-actor `@Observable`: a delegate method called on a background
/// queue cannot be one of its members.
private final class MetadataHeard: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    private let said: @Sendable (String?) -> Void

    init(_ said: @escaping @Sendable (String?) -> Void) { self.said = said }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        // The value is loaded, not read directly: a metadata item's value is a property
        // that may not be in memory yet, and reading it synchronously is the call the
        // framework deprecated for exactly that reason. The delegate is not required to be
        // finished with the group by the time it returns.
        // `AVMetadataItem` is not `Sendable`, and carrying it across an isolation boundary is
        // the cost of reading it asynchronously. This is safe here for one reason: an item
        // delivered to this delegate is finished. The framework built it from bytes
        // that have already gone past, and nothing writes to it again.
        let items = Carried(groups.flatMap(\.items))
        let said = self.said

        Task {
            // ICY announces one string under a handful of keys, depending on the
            // server. The first one that carries anything is the announcement.
            for item in items.it {
                guard let value = try? await item.load(.stringValue),
                      !value.trimmingCharacters(in: .whitespaces).isEmpty
                else { continue }

                said(value)
                return
            }
        }
    }
}


/// Something the framework has finished with, carried across an isolation boundary.
///
/// Only one place uses it, and the reason it is safe is written where it is used. Anything
/// else that uses this should first check that the thing really is finished.
private struct Carried<T>: @unchecked Sendable {
    let it: T
    init(_ it: T) { self.it = it }
}

/// One value behind a lock, for the things a worker has to read while the main actor is
/// busy with something else.
///
/// Small on purpose: it holds what a poll needs to keep a clock moving,
/// and nothing that anybody has to keep in step by hand. It is written from one place,
/// the `didSet` on the thing it mirrors, so there is no second writer to disagree with.
final class Snapshot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
