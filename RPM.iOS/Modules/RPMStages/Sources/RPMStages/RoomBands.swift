import Foundation

/// What the room hears: three envelopes for the light in it, and a run of log-spaced
/// bands for the spectrum drawn across it.
///
/// Ported from `RPM.Core/Viz/RoomBands.cs`, which both C# apps share so that the
/// desktop's room and the phone's are one picture reading one measurement. Two apps
/// folding a spectrum with two sets of arithmetic would show two different rooms, however
/// alike the drawing was. The iOS app is the third app to use the same measurement.
///
/// Nothing here knows where the samples come from. It is handed a tap, taken at the
/// playhead rather than at the decoder, so the picture is in step with the sound.
public final class RoomBands {

    /// Columns in the run, and so one reading per bar. Sampling fewer columns than there
    /// are bars would make several bars read the same place in the curve and stand at the
    /// same height, so the run would look like blocks. **One bar is one frequency band.**
    public static let bands = 128

    // ── what the light answers to ──

    /// The low end that swells the figures: bins 1..12 of the middle window is roughly
    /// 20 to 260 Hz, which is the kick and the bass and nothing above them.
    private static let bassFrom = 1, bassUpto = 12

    /// The middle, which drives the second family of figures: bins 20..90 is roughly
    /// 430 Hz to 1.9 kHz, where the voice and most of what is played actually sit. It is
    /// kept apart from the bass on purpose: two families driven by one envelope breathe as
    /// one body.
    private static let midFrom = 20, midUpto = 90

    /// The air, which drives the third family: bins 116..325 of the **short** window is
    /// roughly 5 to 14 kHz: cymbals, hats, the breath on a consonant, and nothing that
    /// carries a tune.
    ///
    /// It is read from the short window, unlike the two above it, and that is the whole
    /// reason the third family exists as its own thing. What lives up here is transient: a
    /// hat opens and shuts within forty milliseconds, and a 46 ms window smears it into
    /// the sound before it.
    private static let airFrom = 116, airUpto = 325

    private static let ranges = 3

    /// Where the ranges meet, in Hz.
    ///
    /// The bottom range stops at 430 Hz: bass fundamentals live under it and a voice does
    /// not. The top range begins at 5 kHz, because 2.4 kHz is presence (the edge of a
    /// snare, the consonants of a voice), and all of that belongs to the middle of a mix
    /// however high it sounds.
    private static let rangeHz: [Double] = [20, 430, 5000, 16000]

    /// How much of the run's **width** each range is given.
    ///
    /// **This is a layout, not an accident**, and it is the difference between a
    /// spectrum and a wall. A straight log scale over these bins spends half the run
    /// below 480 Hz, so every kick would draw a solid block across the left of the screen,
    /// all of it at the same height, while everything above two kilohertz would be squeezed
    /// into the last inch and look like a flat line.
    private static let rangeWidth: [Float] = [0.45, 0.35, 0.20]

    /// How hard the run answers to what it hears, at its two ends and at its middle.
    ///
    /// **A well rather than three steps.** The drive falls away gradually from the
    /// bottom of the run into the middle and climbs back out of it to the top, so there
    /// is no seam where one range hands over to the next. The two ends are not the
    /// same: the bass is the loudest thing in nearly every mix and does not need the
    /// help; the top end does.
    private static let driveLow: Float = 0.80
    private static let driveHigh: Float = 1.00
    private static let driveMiddle: Float = 0.16

    /// How tall the rim stands, so the run finishes on a rise instead of at a wall.
    ///
    /// This is a curve, not a pair of per-range numbers. Per-range numbers (for example
    /// one for the middle and a half for the top) would multiply the two bars on either
    /// side of the boundary by figures that differ by a factor of two, and draw a step
    /// straight down the picture at exactly 5 kHz.
    private static let leanRim: Float = 1.25

    /// Where a range's own peak lands on the knee's input. Chosen so the loudest bar in
    /// a loud passage sits near four fifths of the height.
    private static let rangeReference: Float = 6

    /// How completely a range follows its own level. **The whole difference between a
    /// spectrum and a meter pinned at the top.** At one, every passage is drawn at the
    /// same height because the range is always measured against itself; below one the
    /// gain follows the peak's root instead, so the ranges stay balanced against each
    /// other but a quiet passage is still visibly a quiet passage.
    private static let rangeAdapt: Float = 0.40

    /// The quietest a range's peak may be taken as. Without it a silent passage winds
    /// the gain up until the noise floor is drawn as music.
    private static let rangeFloor: Float = 0.02

    /// Which band each range starts at, and the middle band of each: a range's gain is
    /// **measured** across the whole range but **applied** at its centre.
    private static let rangeBand = buildRangeBands()
    private static let rangeCentre = buildRangeCentres()

    // ── the three windows ──

    private let low: AnalysisWindow
    private let mid: AnalysisWindow
    private let high: AnalysisWindow

    private var raw = [Float](repeating: 0, count: RoomBands.bands)
    private var curve = [Float](repeating: 0, count: RoomBands.bands)
    private var drawn = [Float](repeating: 0, count: RoomBands.bands)

    private var rangePeak: [Float] = [0.30, 0.20, 0.12]
    private var rangeGain: [Float] = [1, 1, 1]

    private var bassLevel: Float = 0
    private var bassHold: Double = 0
    private var midLevel: Float = 0
    private var midHold: Double = 0
    private var airLevel: Float = 0
    private var airHold: Double = 0

    /// Three windows, one per range, because no single window suits the whole of music.
    /// The length of a window buys frequency resolution and spends time resolution, and
    /// the bottom and the top of a spectrum want opposite ends of that bargain:
    ///
    /// - **low, 8192**: 5.4 Hz bins, a 186 ms window. Below 430 Hz the notes of a bass
    ///   line are a few hertz apart, so resolution is everything; and a low note lasts
    ///   far longer than the window, so hearing that far back costs nothing visible.
    /// - **mid, 2048**: 21.5 Hz bins, a 46 ms window. The balanced middle.
    /// - **high, 1024**: 43.1 Hz bins, a 23 ms window. Above 5 kHz nothing needs
    ///   telling apart to the hertz, and what is up there is cymbals and transients.
    ///
    /// ## There are no delays here
    ///
    /// The C# version holds its long window back through three ticks, and it needs to. Its
    /// tap fills forward **from** the playhead, so a window's contents are audio that
    /// has not been heard yet: a change appears in the long window up to 186 ms before
    /// it reaches the speakers, and the bass would move before the kick is heard.
    ///
    /// **This tap trails.** It hands over what has just been played, so every window
    /// ends at the present moment and a change appears in all three at the instant it
    /// is heard, whatever their lengths. The delay exists to undo a look-ahead that this
    /// version does not have, and adding it here would *introduce* the fault it cures
    /// there.
    ///
    /// The opposite correction, where the short windows wait for the long one, is also
    /// wrong. The long window is not late; it is **slower**, because a change is one part
    /// in 8192 of it on the first tick and grows from there. That is a ramp, not a lag, and
    /// waiting does not fix a ramp. On a 440 Hz onset with no waits at all, the two ends
    /// of the run move on the same tick, and every wait added pushes the top end later by
    /// exactly that many ticks.
    public init(rate: Int) {
        low = AnalysisWindow(rate: rate, frame: 8192, bins: 160, waits: 0)
        mid = AnalysisWindow(rate: rate, frame: 2048, bins: 256, waits: 0)
        high = AnalysisWindow(rate: rate, frame: 1024, bins: 384, waits: 0)
    }

    /// Where the played samples come from. Answers false when there is nothing at the
    /// playhead yet, which is most of the first moment of a track.
    public var tap: ((inout [Float]) -> Bool)?

    /// The low end, enveloped: the figure the room is lit by. **It is already the right
    /// number for lighting**: a held peak with a fast attack and a slow release, so a
    /// kick pushes it up and lets it fall. The raw level would flicker at whatever rate
    /// the drummer plays.
    public var bass: Float { bassLevel }

    /// The middle, on its own envelope. Quicker than the bass in both directions: what
    /// it drives is a family of small figures that should dart where the big ones swell.
    public var middle: Float { midLevel }

    /// The air. Quicker again and barely held at all, because what it answers to has no
    /// sustain to speak of.
    public var air: Float { airLevel }

    /// The run, 0 to 1 a band, log spaced and ready to draw.
    public var run: [Float] { drawn }

    /// Reads the playing block, keeps the three envelopes, and folds the spectrum into
    /// the log-spaced bands the bars are cut from.
    ///
    /// `now` is the caller's own clock in seconds. The holds are measured against it,
    /// so whatever owns the frames owns the time as well. `playing` says whether there
    /// is anything to hear: **silence eases the run down rather than cutting it**,
    /// because a spectrum that falls to nothing the instant the music stops reads as the
    /// picture breaking rather than as the room going quiet.
    public func update(now: Double, playing: Bool) {
        low.update(tap: tap, playing: playing)
        mid.update(tap: tap, playing: playing)
        high.update(tap: tap, playing: playing)

        // Both of the first two envelopes are read from the **middle** window, on purpose:
        // it is the length that these were tuned against, so the figures answer to a kick
        // as promptly as they do on the desktop. Reading the bass envelope from the long
        // window would be wrong. Its 186 ms buys frequency resolution that the bars need,
        // and costs the promptness that the lighting depends on.
        let spectrum = mid.level

        var loud: Float = 0
        for at in Self.bassFrom..<Self.bassUpto { loud += spectrum[at] }
        loud = min(1, loud / Float(Self.bassUpto - Self.bassFrom) * 1.35)

        if loud > bassLevel {
            bassLevel += (loud - bassLevel) * 0.42
            bassHold = now + 0.10
        } else if now >= bassHold {
            bassLevel += (loud - bassLevel) * 0.055
        }

        var centre: Float = 0
        for at in Self.midFrom..<Self.midUpto { centre += spectrum[at] }
        centre = min(1, centre / Float(Self.midUpto - Self.midFrom) * 1.9)

        if centre > midLevel {
            midLevel += (centre - midLevel) * 0.50
            midHold = now + 0.06
        } else if now >= midHold {
            midLevel += (centre - midLevel) * 0.11
        }

        // The air, from the **short** window: the only one of the three that hears a
        // cymbal as an edge rather than as a smear. Its gain is the largest of the three,
        // because there is really less energy up here and the band is wide, so most of the
        // bins averaged in are near silent even while the cymbals are playing. Measured
        // without the gain, it never leaves the floor.
        let top = high.level
        var bright: Float = 0
        for at in Self.airFrom..<Self.airUpto { bright += top[at] }
        bright = min(1, bright / Float(Self.airUpto - Self.airFrom) * 3.0)

        if bright > airLevel {
            airLevel += (bright - airLevel) * 0.62
            airHold = now + 0.03
        } else if now >= airHold {
            airLevel += (bright - airLevel) * 0.16
        }

        foldTheRun()
        measureTheRanges()
        drawTheRun()
    }

    /// Log-spaced bands, as the music is, **but each range is laid out across the width it
    /// was given** instead of all three sharing one curve, which would let the bass take
    /// half the screen.
    private func foldTheRun() {
        for range in 0..<Self.ranges {
            let from = Self.rangeBand[range], upto = Self.rangeBand[range + 1]
            let lowHz = Self.rangeHz[range], highHz = Self.rangeHz[range + 1]
            let span = highHz / lowHz
            let count = Double(upto - from)

            for band in from..<upto {
                let at = Double(band - from)
                raw[band] = fold(lowHz * pow(span, at / count),
                                 lowHz * pow(span, (at + 1) / count))
            }
        }

        // A light three-tap smoothing across the run before anything is measured.
        // Neighbouring bands of real music **are** related (a note is not one bin wide, and
        // neither is a cymbal), so drawing each band as if it were independent of its two
        // neighbours turns a coherent envelope into noise. The smoothing is light enough
        // that no two bars get the same number.
        for band in 0..<Self.bands {
            let before = raw[max(0, band - 1)]
            let after = raw[min(Self.bands - 1, band + 1)]
            curve[band] = before * 0.25 + raw[band] * 0.50 + after * 0.25
        }
    }

    /// Each range against its own recent peak. The peak rises quickly and falls over
    /// seconds, so a range settles to the level the music is actually at, instead of being
    /// scaled by whatever the loudest part of the whole run does.
    private func measureTheRanges() {
        for range in 0..<Self.ranges {
            let from = Self.rangeBand[range], upto = Self.rangeBand[range + 1]

            var peak: Float = 0
            for at in from..<upto { peak = max(peak, curve[at]) }

            rangePeak[range] += (peak - rangePeak[range]) * (peak > rangePeak[range] ? 0.40 : 0.014)
            rangeGain[range] = min(24, max(1,
                Self.rangeReference / pow(max(rangePeak[range], Self.rangeFloor), Self.rangeAdapt)))
        }
    }

    /// One pass down the whole run. **Nothing here is decided by which range a band
    /// falls in**: the gain is eased between the ranges' centres, the drive is a well
    /// across the width, and the lean is a curve that reaches one exactly where the top
    /// range begins. The ranges still measure themselves separately, but their
    /// boundaries are not drawn into the picture.
    private func drawTheRun() {
        for band in 0..<Self.bands {
            let along = Float(band) / Float(Self.bands - 1)

            // One at either end of the run and zero dead centre, so the drive eases
            // down from the bass into the middle and back up into the top without a seam.
            let dip = 1 - 4 * along * (1 - along)
            let drive = Self.driveMiddle
                      + ((along < 0.5 ? Self.driveLow : Self.driveHigh) - Self.driveMiddle) * dip

            // **Gain first, then the curve.** The gain puts this part of the run where
            // it can be seen. The power above one then pushes the quiet bands back down,
            // which leaves a visible gap between a bar and its neighbour. A power under
            // one would lift all bands toward the loudest and the run would flatten into
            // a block.
            let x = pow(curve[band] * gain(at: band), 1.15) * drive * Self.lean(at: along)

            // The knee that cannot clip: x/(1+x) keeps rising but never reaches 1. It gives
            // half height at one, two thirds at two, four fifths at four, and no value
            // reaches the top.
            let v = x / (1 + x)

            // A second ease, on the **shape** rather than on the bins. The rise is almost
            // immediate, and the fall is quick enough that a bar is down before the next
            // hit, instead of being caught halfway and never reaching the floor.
            drawn[band] += (v - drawn[band]) * (v > drawn[band] ? 0.94 : 0.80)
        }
    }

    /// The gain for one band, **eased between the ranges, not switched at their edges**.
    /// If a range's gain were applied to every band in it, with a jump to a different
    /// number at the boundary, the boundary would be drawn.
    private func gain(at band: Int) -> Float {
        let centre = Self.rangeCentre
        let band = Float(band)

        if band <= centre[0] { return rangeGain[0] }
        if band >= centre[Self.ranges - 1] { return rangeGain[Self.ranges - 1] }

        for range in 0..<(Self.ranges - 1) where band <= centre[range + 1] {
            var t = (band - centre[range]) / (centre[range + 1] - centre[range])
            t = t * t * (3 - 2 * t)
            return rangeGain[range] + (rangeGain[range + 1] - rangeGain[range]) * t
        }

        return rangeGain[Self.ranges - 1]
    }

    /// The lean at a point along the run: flat until the top range begins, then a
    /// smoothstep climb to the rim. One at the boundary, so there is no step there.
    private static func lean(at along: Float) -> Float {
        let start = Float(rangeBand[ranges - 1]) / Float(bands - 1)
        guard along > start else { return 1 }

        var t = (along - start) / max(1e-4, 1 - start)
        t = t * t * (3 - 2 * t)
        return 1 + (leanRim - 1) * t
    }

    /// The level across a span of frequency, read from whichever transform resolves it
    /// best. **The crossovers are the range edges**, so no range is ever drawn from two
    /// transforms and there is no seam inside a range.
    private func fold(_ lowHz: Double, _ highHz: Double) -> Float {
        let window = highHz <= Self.rangeHz[1] ? low : highHz <= Self.rangeHz[2] ? mid : high
        let level = window.level
        let last = window.bins - 1

        let from = lowHz / window.binHz
        let upto = highHz / window.binHz

        guard upto - from >= 1 else {
            // Narrower than a bin, which is still possible at the very bottom even with the
            // long window. **Read between the bins instead of rounding to one**: rounding
            // would give the first fifteen bars the same number and draw them as a block.
            let at = (from + upto) * 0.5
            let first = min(max(Int(at), 0), last - 1)
            let over = Float(at - Double(first))
            return level[first] * (1 - over) + level[first + 1] * over
        }

        let first = min(max(Int(from), 0), last)
        let end = min(max(Int(upto), first + 1), last + 1)

        var sum: Float = 0
        for at in first..<end { sum += level[at] }
        return sum / Float(end - first)
    }

    private static func buildRangeBands() -> [Int] {
        var edges = [Int](repeating: 0, count: ranges + 1)
        var over: Float = 0

        for range in 0..<ranges {
            over += rangeWidth[range]
            edges[range + 1] = min(bands, max(edges[range] + 1, Int((over * Float(bands)).rounded())))
        }

        edges[ranges] = bands
        return edges
    }

    private static func buildRangeCentres() -> [Float] {
        (0..<ranges).map { Float(rangeBand[$0] + rangeBand[$0 + 1] - 1) * 0.5 }
    }
}

/// One analysis window: a frame of played samples, the transform of it, and the levels
/// it hands back.
///
/// **Every window maps the same dB range onto 0 to 1 and settles at the same
/// rate**, so three of different lengths hand back levels on one scale and the run does
/// not step where it crosses from one to the next. All that differs between them is how
/// finely they resolve frequency and how far back in time they hear.
final class AnalysisWindow {
    private static let floorDb = -84.0
    private static let ceilingDb = -20.0

    /// The window length every other one is referred to, so all three agree about the
    /// level of the same music.
    private static let reference = 2048

    /// How much of the previous reading carries over, so a bin settles instead of
    /// strobing.
    private static let smoothing: Float = 0.5

    private let frame: Int
    private var wave: [Float]
    private let shape: [Float]
    private var re: [Double]
    private var im: [Double]

    private var now: [Float]
    private var line: [[Float]]
    private let straightThrough: Bool
    private var at = 0

    /// Bins kept, and how wide each is in Hz.
    let bins: Int
    let binHz: Double

    /// The levels to draw from, delayed to the same instant as the other windows.
    private(set) var level: [Float]

    init(rate: Int, frame: Int, bins: Int, waits: Int) {
        self.frame = frame
        self.bins = bins

        wave = [Float](repeating: 0, count: frame)
        shape = Spectrum.hann(frame)
        re = [Double](repeating: 0, count: frame)
        im = [Double](repeating: 0, count: frame)

        now = [Float](repeating: 0, count: bins)
        level = [Float](repeating: 0, count: bins)
        binHz = Double(rate) / Double(frame)

        line = Array(repeating: [Float](repeating: 0, count: bins), count: max(1, waits))
        straightThrough = waits <= 0
    }

    /// Reads the playing block and folds it down. A frame the tap cannot fill (the first
    /// fraction of a second of a track) eases the held reading down instead of cutting
    /// it, which is also what silence does.
    func update(tap: ((inout [Float]) -> Bool)?, playing: Bool) {
        if !playing || tap == nil || !tap!(&wave) {
            for at in 0..<bins { now[at] *= Self.smoothing }
        } else {
            for at in 0..<frame {
                re[at] = Double(wave[at] * shape[at])
                im[at] = 0
            }

            Spectrum.transform(&re, &im)

            // **Bins of a shorter window are wider**, so each holds more of a broadband
            // signal and reads hotter, about 3 dB per halving. Without this correction the
            // windows would disagree about the level of the same music, and the disagreement
            // would fall exactly on the crossovers, where it is drawn as a step.
            let bandwidth = Double(frame) / Double(Self.reference)

            for at in 0..<bins {
                let power = (re[at] * re[at] + im[at] * im[at])
                          / (Double(frame) * Double(frame)) * bandwidth
                let db = 10 * log10(power + 1e-12)
                let heard = Float(min(1, max(0, (db - Self.floorDb) / (Self.ceilingDb - Self.floorDb))))

                // Peak-fast, fall-slow: a rising bin jumps, a falling one eases down.
                now[at] = heard > now[at] ? heard : now[at] * Self.smoothing + heard * (1 - Self.smoothing)
            }
        }

        guard !straightThrough else {
            level = now
            return
        }

        // Through the delay line: output the oldest reading, then store this one in its
        // place.
        level = line[at]
        line[at] = now
        self.at = (self.at + 1) % line.count
    }
}
