import Foundation
import Observation
import os.log
import QuartzCore
import RPMAudio
import RPMDesign
import RPMStages

/// Reads the music for the picture: it connects the engine's audio tap to the run of frequency
/// bands.
///
/// **The reading is not done on the main thread.** Three transforms (sizes 8192, 2048 and 1024)
/// forty times a second is a lot of arithmetic, and the main thread draws the app. The loop runs
/// at utility priority and hands the finished run over, so the main thread only draws it.
///
/// **It reads nothing while it is stopped.** Start and stop are the whole contract: a phone gets
/// hot from running work whether or not the screen shows it. The Uno app's stage follows the same
/// rule.
@MainActor
@Observable
public final class RoomReader {
    /// The room, as the transition between the last two readings, not only the latest one.
    ///
    /// **The measurement rate is not the screen refresh rate.** This property connects the two. The
    /// run and the three envelopes are measured forty times a second (`RoomBands` is tuned to that
    /// rate, and all three apps share it). The view that draws them calls `RoomRamp.read(_:)` at
    /// the time of its own frame. The picture therefore updates at the screen rate, without the
    /// music being read at that rate.
    ///
    /// The envelopes are stored together with the run, not separately: a bar and the light behind it
    /// would disagree about the same kick if they were read at different times. The Uno app's room
    /// shares its low end for the same purpose through `IPegasusRoom.Bass`.
    public private(set) var ramp = RoomRamp.still

    /// The colours this record paints the room in, stored as a transition and not as one value.
    /// The palette arrives in one step, because a cover is decoded once, and a dissolve hides that
    /// step.
    ///
    /// **Read at the time the frame is drawn**, like ``ramp``. There is a second reason beyond
    /// smoothness: nothing in this class advances it, so a silent engine cannot freeze it. If it
    /// were eased inside the loop below, it would not move until sound had been heard. A sheet
    /// opened on a paused track, or while the sound plays on a speaker in another room, would then
    /// stay on the app's blue whatever colour the sleeve has. See ``RoomDissolve``.
    public private(set) var colours = RoomDissolve.still

    /// The colours as they are now, for code that needs them at the current moment and not at a
    /// frame's time.
    public var palette: RoomPalette { colours.read(CACurrentMediaTime()) }

    /// How often the run is read. **Forty times a second, which must match the Uno app.**
    ///
    /// The rate cannot be lower, even for bars of this size, and the frame rate is not the reason.
    /// Every ease in `RoomBands` (the bins, the range peaks, and the run's own attack and release)
    /// is a fraction taken per update, not per second, and all were tuned for a 25 ms tick. At half
    /// the rate the bars would not only arrive half as often. They would also take twice as long in
    /// real time to fall, so the run would trail a kick instead of answering it.
    ///
    /// This is a number of seconds and not a `Duration`, because it has two uses: the deadline of
    /// the sleep, and the length of the transition that a drawn frame lies within. If these were
    /// written as two values, they could drift apart, and a ramp given the wrong length would
    /// arrive early and then wait.
    ///
    /// `nonisolated` because the loop is not isolated: it reads this value when it computes its next
    /// deadline, which is plain arithmetic and not an `await`. A constant is not state, so it
    /// should not require an actor hop.
    private nonisolated static let beat = 0.025

    private var loop: Task<Void, Never>?

    /// Creating a reader does no work, so it can be created anywhere. A view can therefore hold it
    /// in `@State` without the creation being a main-actor call.
    public nonisolated init() {}

    /// Sets the colours that the art pipeline read from the sleeve. Any of them may be nil (a
    /// black-and-white photograph has no colour to give), and then the room keeps the app's own
    /// blue.
    public func paint(tint: RGB?, glow: RGB?, shade: RGB?) {
        colours = colours.toward(
            .from(tint: tint?.asFloats, glow: glow?.asFloats, shade: shade?.asFloats),
            at: CACurrentMediaTime())
    }

    /// Starts listening to a player and reading what it plays.
    public func start(with player: Player) {
        guard loop == nil else { return }

        player.draw(true)
        guard let sound = player.drawing else { return }

        RoomTally.begun()

        loop = Task.detached(priority: .utility) { [weak self] in
            var room: RoomBands?
            var tally = RoomTally()

            // The reader's own clock. The beat is measured against it and not against the number of
            // loop iterations.
            let began = CACurrentMediaTime()
            var due = ContinuousClock.now

            while !Task.isCancelled {
                // **The sample rate comes from the engine**, and it is not known until sound has
                // been heard. A room folded with the wrong rate draws the wrong frequencies.
                if room == nil, sound.rate > 0 {
                    let made = RoomBands(rate: Int(sound.rate))
                    made.tap = { frame in sound.fill(&frame) }
                    room = made
                }

                if let room {
                    let asked = RoomTally.on ? CACurrentMediaTime() : 0

                    let playing = await MainActor.run { player.isPlaying }
                    let answered = RoomTally.on ? CACurrentMediaTime() : 0

                    // **Real elapsed seconds**, not one beat counted per iteration. The envelope
                    // holds are measured in seconds against this (a kick is held for 100 ms). If
                    // the loop assumed 25 ms per iteration but took 40 ms, every hold would last
                    // 60% longer than intended.
                    room.update(now: CACurrentMediaTime() - began, playing: playing)

                    let drawn = RoomReading(run: room.run, bass: room.bass,
                                            middle: room.middle, air: room.air)
                    let folded = CACurrentMediaTime()

                    await MainActor.run {
                        guard let self else { return }

                        // **Start from where the last transition ended**, which is where the picture
                        // actually is. Do not start from the previous reading: a frame that arrived
                        // late has already moved past it.
                        self.ramp = RoomRamp(from: self.ramp.to, to: drawn,
                                             at: folded, over: Self.beat)
                    }

                    if RoomTally.on {
                        // The two waits are counted together because they wait for the same thing:
                        // asking whether the music is playing, and handing the run over, both queue
                        // behind whatever the main thread is drawing.
                        tally.read(folding: folded - answered,
                                   waiting: (answered - asked) + (CACurrentMediaTime() - folded))
                    }
                }

                // **Sleep until a deadline, not for a duration.** Sleeping for the beat after the
                // work makes each cycle the beat plus the work plus any sleep overshoot. With a
                // 50 ms beat this measured about 17 reads a second instead of 20. A deadline
                // counts the work as part of the beat instead of adding it on top.
                due = due.advanced(by: .seconds(Self.beat))

                // A read that overran its beat does not try to catch up on the missed ones: the
                // arithmetic is the same either way and the bars would only jump.
                let now = ContinuousClock.now
                if due < now { due = now.advanced(by: .seconds(Self.beat)) }

                try? await Task.sleep(until: due, clock: .continuous)
            }
        }
    }

    /// Releases the tap. **The engine keeps one listener**, so a reader that is dropped without
    /// calling this leaves the tap running for a picture that nobody is looking at.
    public func stop(_ player: Player) {
        loop?.cancel()
        loop = nil
        ramp = .still

        player.draw(false)
    }

    // There is no `deinit` that cancels the loop: the task is main-actor state, and a `deinit` is
    // not main-actor isolated, so it cannot reach the task. Call `stop`, as the stage does when it
    // shuts down. The loop holds only a weak reference to the reader, so an unstopped reader leaves
    // a task that reads the music and passes it nowhere until the tap is released.
}

extension RGB {
    /// The same colour as the room's calculations need it: each channel from 0 to 1.
    public var asFloats: SIMD3<Float> {
        SIMD3(Float(r) / 255, Float(g) / 255, Float(b) / 255)
    }

    /// The reverse conversion, for the parts of the room that are drawn and not shaded. Values are
    /// clamped to the valid range, because the palette lifts colours and a lift can push a channel
    /// above 1.
    public init(_ colour: SIMD3<Float>) {
        func byte(_ x: Float) -> UInt8 { UInt8(max(0, min(255, x * 255 + 0.5))) }

        self.init(byte(colour.x), byte(colour.y), byte(colour.z))
    }
}

/// Measures how fast the room is really being read.
///
/// When `RPM_STAGE_DIAG` is set (the same switch ``StageClock`` reads, so one flag shows what
/// every drawn look is doing), it prints a line every couple of seconds with the read rate and
/// where the time went.
///
/// **The beat is a target, not a measured rate.** The loop sleeps until a deadline one
/// ``RoomReader/beat`` after the last one, but a read that takes longer than the beat (three
/// transforms plus the time the main actor takes to accept two calls) lowers the real rate. A
/// reader that has slowed to half its rate does not show itself: bars that move and bars that move
/// slowly look the same. For the same reason ``StageClock`` counts its own frames.
///
/// **The two parts are kept apart**, because different things cause them: folding is arithmetic,
/// and waiting is the main thread. Knowing which one uses up the beat is the reason to count at
/// all.
///
/// **It lives outside the reader.** The values are written once per tick from the loop's own
/// thread, and the reader is an `@Observable` on the main actor. A counter stored in the reader
/// would need an actor hop to update, and would redraw every view that watches the room.
private struct RoomTally {
    /// Read once, because it is fixed for the whole launch.
    static let on = ProcessInfo.processInfo.environment["RPM_STAGE_DIAG"] != nil

    private static let log = Logger(subsystem: "com.rpm.player", category: "room")

    /// How often it prints, in seconds.
    private static let every = 2.0

    private var reads = 0
    private var from = CACurrentMediaTime()
    private var folding = 0.0
    private var waiting = 0.0

    /// Prints once, when the reader starts, that counting is on.
    ///
    /// **Without it, silence is ambiguous**: an uncounted reader and a reader that is never reached
    /// look the same, and a wrong switch is the more likely cause.
    static func begun() {
        guard on else { return }
        say("counting the reads")
    }

    /// Prints a line in two ways, so the output is easy to find.
    ///
    /// It goes to the unified log, where it can be filtered by subsystem and read later. A Mac's
    /// `log stream` shows the Mac and the simulators on it, and a physical device needs `--device`
    /// or the Console app. It also goes to standard output, which the Xcode console shows wherever
    /// the app runs.
    private static func say(_ line: String) {
        log.notice("\(line, privacy: .public)")
        print("[room] \(line)")
    }

    /// Records one read: the seconds spent folding the spectrum, and the seconds spent waiting for
    /// the main actor before and after it.
    mutating func read(folding: Double, waiting: Double) {
        reads += 1
        self.folding += folding
        self.waiting += waiting

        let now = CACurrentMediaTime()
        guard now - from >= Self.every else { return }

        Self.say(String(format: "%.1f reads a second, %.1f ms folding, "
                              + "%.1f ms waiting for the main thread",
                        Double(reads) / (now - from),
                        self.folding / Double(reads) * 1000,
                        self.waiting / Double(reads) * 1000))

        reads = 0
        from = now
        self.folding = 0
        self.waiting = 0
    }
}
