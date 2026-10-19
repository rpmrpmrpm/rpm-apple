import Foundation

/// The room at one instant: the run of bands, and the three envelopes the light answers
/// to.
///
/// What `RoomBands` measures, in one piece rather than four. It is one piece because it
/// is read as one: a bar and the light behind it, taken from different ticks, disagree
/// about the same kick. That is visible on the screen even though neither of them is
/// wrong.
public struct RoomReading: Sendable, Equatable {
    /// The run as it is drawn, 0 to 1 a band.
    public var run: [Float]

    /// The three envelopes, as `RoomBands` enveloped them.
    public var bass: Float
    public var middle: Float
    public var air: Float

    /// Nothing heard, which is where a room stands before the first frame lands.
    public static let silent = RoomReading(run: [], bass: 0, middle: 0, air: 0)

    /// The three envelopes alone, which is all a room asks of a reading: the run is for the bars.
    /// Named so that a room lit by the music and one breathing on its own can both be given the
    /// same shape.
    public var levels: (bass: Float, middle: Float, air: Float) { (bass, middle, air) }

    public init(run: [Float], bass: Float, middle: Float, air: Float) {
        self.run = run
        self.bass = bass
        self.middle = middle
        self.air = air
    }
}

/// The room **between** two readings, which is where it is at all but forty instants a
/// second.
///
/// ## The two rates are different, and have to be
///
/// The music is measured forty times a second because that is what the shortest window
/// hears: 1024 samples is 23 ms of audio, so a 25 ms beat steps about one window at a
/// time, and reading faster would only re-transform samples already read. The screen
/// draws sixty times a second, or a hundred and twenty on a phone that can. If a reading
/// were drawn directly, a bar would stand still for a beat and then jump, so the picture
/// would run at forty frames a second however fast the screen is.
///
/// So the reading is not what is drawn. **What is drawn is the travel between the last
/// two readings**, asked for at whatever instant the screen is drawing. The measurement
/// keeps its own rate and stays the one that all three apps share; the motion takes the
/// screen's rate.
///
/// ## What it costs
///
/// **A beat of lag** is the whole cost: a bar arrives at a reading one beat after the
/// reading did, where a staircase arrives half a beat late on average. That is twelve
/// milliseconds, on a picture that nobody compares against a reference, in exchange for
/// motion at the rate the screen can really show. Extrapolating instead would add no lag
/// but would be wrong: a bar drawn past what was measured overshoots every transient and
/// shakes on every steady sound.
public struct RoomRamp: Sendable {
    /// Where the travel starts: the last reading, as it was left standing.
    public let from: RoomReading

    /// ...and where it is headed: the reading that has just landed.
    public let to: RoomReading

    /// When ``to`` landed, on whichever clock ``read(_:)`` is asked with. One clock, and
    /// it has to be monotonic: a wall clock that steps backwards puts every bar back
    /// where it was a moment ago.
    public let at: Double

    /// How long the travel has: the reader's beat, in seconds.
    ///
    /// **Passed in, not assumed.** Only the code that sets the beat knows it, and a ramp
    /// given the wrong value arrives early and waits, or never arrives at all.
    public let over: Double

    /// A room at rest, before anything has been heard.
    public static let still = RoomRamp(from: .silent, to: .silent, at: 0, over: 1)

    public init(from: RoomReading, to: RoomReading, at: Double, over: Double) {
        self.from = from
        self.to = to
        self.at = at
        self.over = over
    }

    /// The room as it stands at `now`.
    ///
    /// Past the end of the travel it is the later reading and nothing else: a beat that
    /// overran leaves a bar holding still, never one carrying on past what was measured.
    public func read(_ now: Double) -> RoomReading {
        guard over > 0 else { return to }

        let phase = (now - at) / over
        guard phase > 0 else { return from }
        guard phase < 1 else { return to }

        // Two runs of different lengths is the first reading after the engine named its
        // rate, and there is nothing to travel between: take the new one whole.
        guard from.run.count == to.run.count else { return to }

        let t = Float(phase)
        var run = to.run
        for band in run.indices {
            run[band] = from.run[band] + (to.run[band] - from.run[band]) * t
        }

        return RoomReading(run: run,
                           bass: from.bass + (to.bass - from.bass) * t,
                           middle: from.middle + (to.middle - from.middle) * t,
                           air: from.air + (to.air - from.air) * t)
    }
}
