import Foundation

/// Where the record is, counted in beats rather than in seconds. ``measured`` says whether
/// that count came from the track's own grid or from a clock standing in for one.
///
/// Ported from `RPM.Core/Viz/VizDirector.cs`.
///
/// **In the iOS app it is always the stand-in.** Nothing here analyses a record: the desktop
/// tracks beats and finds drops, and none of that reaches the iOS app. So the picture cuts
/// and moves, but not to the music. The desktop also handles this case (a record with no
/// beat grid), so it is not a limit that this port added.
public struct BeatClock: Equatable, Sendable {
    /// Beats since the first bar line. Negative before it.
    public let beats: Double
    public let beatsPerBar: Int

    /// Whether the count came from the record's own grid.
    public let measured: Bool

    public init(beats: Double, beatsPerBar: Int, measured: Bool) {
        self.beats = beats
        self.beatsPerBar = beatsPerBar
        self.measured = measured
    }

    /// The tempo the stand-in clock runs at, for a record that has not been analysed. It is
    /// not a guess at THIS record's tempo (there is no such reading), but a pace to cut at
    /// that suits most records.
    public static let freeBpm = 120.0

    /// The clock for a record with no grid: seconds, counted as beats at a steady pace.
    public static func free(_ seconds: Double) -> BeatClock {
        BeatClock(beats: seconds * (freeBpm / 60), beatsPerBar: 4, measured: false)
    }

    /// ...and for a record whose tempo is known. The iOS app has no tempo analysis yet, so
    /// it does not use this.
    public static func at(bpm: Double, seconds: Double) -> BeatClock {
        guard bpm > 0 else { return free(seconds) }

        return BeatClock(beats: seconds * (bpm / 60), beatsPerBar: 4, measured: true)
    }
}

/// One arrangement of the space a marched visualiser is drawing: how many times it is
/// folded around the axis, how far the fold pushes the walls out, how hard it twists as it
/// runs away, how often the cells repeat, and how much metal there is.
///
/// A room is a hash of the section it belongs to, so the same phrase of the same record is
/// always the same room.
///
/// **The six numbers are deliberately not named after any one picture.** The tunnel reads
/// them as its struts and rungs, the kaleidoscope as its mirrors, and the lattice as its
/// cell. So the same phrase of the same record changes all three at the same moment, which
/// is why they share this type.
public struct VizRoom: Equatable, Sendable {
    /// Repeats around the axis, 3 to 9. Three is a corridor; nine is a kaleidoscope.
    public let folds: Float

    /// How far out the fold pushes the walls, in units.
    public let arm: Float

    /// Rotation per unit of depth, radians. The picture corkscrews at this rate.
    public let twist: Float

    /// How often the rungs repeat down the tunnel, in units.
    public let ring: Float

    /// Half-thickness of the metal.
    public let girth: Float

    /// How much of each cell the cut-out cross takes back out of it.
    public let cross: Float

    /// Which of the four solids this room is built from.
    ///
    /// **The room's cross-cut is what picks it.** It is a number that the section already
    /// has, so there is no fifth hash that cannot be traced back to anything. The shape
    /// therefore changes on the same phrase as the fold count and the twist: one change in
    /// several things at once, which is what looks like a change.
    public var solid: Float { min(3.99, (cross - 0.25) / 0.95 * 4).rounded(.down) }

    /// The room the walls are actually in this frame: the section's, slid into over its
    /// first two beats.
    ///
    /// **The fold count is not blended.** Half a fold leaves a seam where the last wedge
    /// meets the first, running the length of the picture, so a look that folds takes the
    /// new count whole and everything else slides.
    public static func blend(_ was: VizRoom, _ now: VizRoom, _ t: Float) -> VizRoom {
        func to(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }

        return VizRoom(folds: now.folds,
                       arm: to(was.arm, now.arm),
                       twist: to(was.twist, now.twist),
                       ring: to(was.ring, now.ring),
                       girth: to(was.girth, now.girth),
                       cross: to(was.cross, now.cross))
    }
}

/// One camera set-up, and the room it is looking at: everything a marched visualiser needs
/// for a frame, worked out from where the record is rather than accumulated frame by frame.
/// So a seek, a pause or a dropped frame gives the same picture that the same instant would
/// give anywhere else.
public struct VizShot: Equatable, Sendable {
    /// The room this section is in, and the one the section before it was in.
    public let now: VizRoom
    public let was: VizRoom

    /// 0 at a section's first beat, 1 once it has settled: how far the walls have moved
    /// from ``was`` to ``now``. A change of room is a fold count sliding into another, not
    /// a cut, which is the one thing on screen that is not on the beat.
    public let blend: Float

    /// Which colour ramp this section is lit with.
    public let palette: Int

    /// The camera's roll about the tunnel's axis, radians.
    public let orbit: Float

    /// How far the camera travels per beat, in units, in THIS shot.
    public let advance: Float

    /// How far it has travelled altogether, in units. **Not ``advance`` times ``beats``**: a
    /// cut picks a new speed, and multiplying the whole count by the new speed moves the
    /// camera to where it WOULD have been if it had always gone that fast, which is a jump
    /// of tens of units on every cut. This value is the speeds actually flown, added up.
    public let travelled: Float

    /// Field of view, as the distance to the projection plane.
    public let fov: Float

    /// How far the aim wanders off the axis.
    public let sway: Float

    /// Beats since the first bar line, fractional.
    public let beats: Float

    /// One on the beat, falling to 0 by the next one.
    public let pulse: Float

    /// One where the beat has just come back after a breakdown, falling to 0 over the
    /// bars after it.
    public let drop: Float
}

/// The cutting room, shared by the marched visualisers. It holds no state and draws
/// nothing: given where the record is, it says where the camera is standing, which
/// arrangement of the space is up, and how hard this instant is hitting.
///
/// **The shape of the edit is the record's own.** The camera cuts every ``beatsPerCut``
/// beats and the walls move every ``barsPerSection`` bars, so on a record with a grid every
/// change lands on a beat and most of them on a bar line. What each cut goes to is a hash of
/// the cut's number: the same bar of the same record always cuts to the same camera, which
/// makes the sequence look like an edit and not like a random shuffle.
///
/// It is pure and kept in this package so the edit can be checked without a surface, for
/// the same reason as ``RibbonSea`` and ``ChladniPlate``.
public enum VizDirector {
    /// Colour ramps to light a section with.
    public static let palettes = 4

    /// Beats between camera cuts. Two bars of four.
    public static let beatsPerCut = 8

    /// Bars between changes of room. Eight is the phrase most records are built in.
    public static let barsPerSection = 8

    /// How long the walls take to move to the new room, in beats.
    private static let blendBeats = 2.0

    /// How long a drop keeps the room wide open, in beats.
    private static let dropBeats = 8.0

    /// The frame's shot.
    ///
    /// - Parameters:
    ///   - clock: where the record is, in beats.
    ///   - beatsSinceDrop: beats since the beat came back in, or negative where the record
    ///     has no drops. Only the first ``dropBeats`` count.
    public static func shot(_ clock: BeatClock, beatsSinceDrop: Double = -1) -> VizShot {
        let beats = clock.beats
        let perBar = max(1, clock.beatsPerBar)
        let perSection = Double(perBar * barsPerSection)

        // Floor, not truncate: before the first bar line the count is negative, and
        // truncation would hold cut 0 for twice as long as every other cut and mirror the
        // edit around it.
        let cut = Int((beats / Double(beatsPerCut)).rounded(.down))
        let section = Int((beats / perSection).rounded(.down))

        let a = hash(cut, 0), c = hash(cut, 2)

        // Where in the beat we are, as a fall from 1 to 0: the pulse that everything on
        // screen is struck by.
        let intoBeat = beats - beats.rounded(.down)
        let pulse = Float((1 - intoBeat) * (1 - intoBeat))

        let drop = beatsSinceDrop < 0 || beatsSinceDrop > dropBeats
            ? Float(0)
            : Float(1 - beatsSinceDrop / dropBeats)

        let intoSection = beats - Double(section) * perSection
        let blend = Float(min(1, max(0, intoSection / blendBeats)))

        return VizShot(
            now: room(section),
            was: room(section - 1),
            blend: blend,
            palette: Int(hash32(section, 11) % UInt32(palettes)),
            orbit: (a - 0.5) * 2.4,
            // A drop flies harder: the same room, at a higher speed. It is NOT folded into
            // the distance travelled, for the same reason a cut is not: a speed that fades
            // in over eight beats, multiplied by the whole count, drags the camera backwards
            // as it fades.
            advance: speed(cut),
            travelled: travelled(beats),
            fov: 0.55 + 0.45 * c,
            // ...and it opens the shot out: the aim stops wandering and the camera looks
            // straight down the tunnel.
            sway: (1 - drop) * (0.08 + 0.5 * hash(cut, 3)),
            beats: Float(beats),
            pulse: pulse,
            drop: drop)
    }

    /// How fast this shot flies, in units per beat. A hash of the cut, so a shot keeps its
    /// speed and the next one is its own.
    private static func speed(_ cut: Int) -> Float { 0.9 + 1.4 * hash(cut, 1) }

    /// How far the camera has flown by this beat: every completed shot at the speed it was
    /// flown at, plus however far into the current one we are.
    ///
    /// Derived, like everything else here, so a seek arrives at the same place that playing
    /// through would have reached. It is derived by ADDING UP, not by multiplying, and that
    /// is the whole point.
    ///
    /// The loop is over shots, not beats: each shot is two bars, so a long record is a few
    /// hundred turns of the loop once a frame. The cap is a backstop against a position that
    /// has gone nonsensical, not a real limit: an hour at 200 bpm is fifteen hundred shots.
    public static func travelled(_ beats: Double) -> Float {
        let cut = Int((beats / Double(beatsPerCut)).rounded(.down))
        let span = min(20_000, max(-64, cut))

        var sum = 0.0
        if span >= 0 {
            for i in 0..<span { sum += Double(speed(i)) }
        } else {
            for i in span..<0 { sum -= Double(speed(i)) }
        }
        sum *= Double(beatsPerCut)

        return Float(sum + Double(speed(span)) * (beats - Double(span * beatsPerCut)))
    }

    /// The arrangement this section is in. Every number is a hash of the section, so a room
    /// is reproducible: the eighth phrase of a record is the same eighth phrase tomorrow.
    public static func room(_ section: Int) -> VizRoom {
        VizRoom(
            // Rounded, so the fold count is a whole number of repeats. A fraction leaves a
            // seam where the last wedge meets the first, running the length of the tunnel.
            folds: (3 + 6 * hash(section, 21)).rounded(),
            arm: 2.2 + 2.6 * hash(section, 22),
            twist: 0.05 + 0.30 * hash(section, 23),
            ring: 1.6 + 2.8 * hash(section, 24),
            girth: 0.035 + 0.075 * hash(section, 25),
            cross: 0.25 + 0.95 * hash(section, 26))
    }

    /// A number from 0 to 1 for this section (or cut) and this question. It is deterministic,
    /// and spread enough that two questions about the same number do not get the same answer.
    private static func hash(_ n: Int, _ which: Int) -> Float {
        Float(hash32(n, which) & 0xFF_FFFF) / Float(0x100_0000)
    }

    /// An integer mix, not a sine: every machine gives the same result to the bit, and the
    /// tests can say what the eighth phrase looks like without running a GPU.
    private static func hash32(_ n: Int, _ which: Int) -> UInt32 {
        var h = UInt32(truncatingIfNeeded: n) &* 2_654_435_761 &+ UInt32(truncatingIfNeeded: which) &* 2_246_822_519
        h ^= h >> 15
        h &*= 2_246_822_519
        h ^= h >> 13
        h &*= 3_266_489_917
        h ^= h >> 16

        return h
    }
}
