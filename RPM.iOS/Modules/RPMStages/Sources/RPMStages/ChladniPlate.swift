import Foundation

/// A plate of sand, and the music playing it: the physics, with nothing that draws.
///
/// Ported from `RPM.Core/Viz/ChladniPlate.cs`, figure for figure.
///
/// Ernst Chladni's experiment, 1787: scatter sand on a metal plate, sound it, and the
/// grains bounce away from everywhere the plate is moving and pile up along the lines
/// where it stands still. The figure that appears is not a picture OF the sound, it is
/// the sound, made of the only thing that will hold still in it.
///
/// A plate does not hold one note. It has a whole set of modes, and a real sound wakes
/// several at once. So the displacement is the SUM of its modes, each weighted by how
/// much music is sounding it, and the sand settles on the zeros of that sum. That is the
/// whole point: a bass line and a hi-hat wake different modes than a dense chord does, so
/// the figure belongs to the balance of THIS spectrum and no other.
///
/// - a steady passage settles into a clean figure, because the sand has time to find the
///   lines
/// - a change of arrangement wakes different modes and the figure dissolves and re-forms
/// - a loud passage throws the grains into a haze before they fall back
/// - silence leaves the sand exactly where it lies. Nothing breathes, nothing pulses,
///   nothing fades in. The last figure the music drew simply stays there, and that is
///   what silence looks like.
///
/// It is kept apart from the drawing because all three apps run it and none can share
/// another's drawing: the desktop puts these grains in a vertex buffer and draws them with
/// OpenGL, the Uno phone app gives the same array to Skia as points, and the iOS app draws
/// them itself. The physics is the visualiser; the rest is a plotter.
public final class ChladniPlate {
    /// The plate's modes, as (n, m) pairs, ordered by n² + m². This is how a plate's own
    /// resonances order themselves, so the list runs from the lowest note the plate can
    /// hold to the highest. Each mode is given the band of the spectrum that would sound it.
    private static let modes: [(n: Int, m: Int)] = [
        (2, 3), (3, 4), (2, 5), (4, 5), (3, 6), (4, 7), (5, 8), (6, 9),
    ]

    /// cos and sin of n·π·x, sampled once over the plate. The modes are whole numbers, so
    /// these never change: the whole per-frame cost of the field is table lookups and
    /// multiply-adds, no trigonometry at all.
    private static let table = 2048

    // How the sand travels, and this is the part that decides whether the figure ARRIVES
    // steadily or arrives fast and then slows down.
    //
    // A hop is a FIXED size. It does not scale with how hard the plate is shaking a
    // grain. If it did, grains far from a node would arrive quickly while grains almost
    // there would move very slowly, and the whole figure would be exponential: nearly
    // finished in seconds, then minutes of changes too small to see. With a fixed hop, the time a grain takes to arrive
    // is simply how far it has to go.
    //
    // `rate` is plate widths a second, `aim` how much of each hop is pointed at the
    // quiet, `scatter` how much is thrown at random.
    private static let rate: Float = 0.0024
    private static let aim: Float = 0.55
    private static let scatter: Float = 1.30

    /// What counts as arriving, as a DISTANCE to the nodal line rather than a
    /// displacement threshold: a grain is home when it is within this far of the line,
    /// which is |u| / |grad u| away from it. Written as a displacement instead, the same
    /// number means a different distance wherever the plate is steeper or flatter, and on
    /// a plate holding eight modes at once it means most of the surface counts as still
    /// before anything has moved at all.
    private static let capture: Float = 0.008

    private var cosine: [Float]
    private var sine: [Float]

    /// How strongly each mode is being sounded right now. THIS is the figure: the sand
    /// settles on the zeros of the sum of the modes, so the shape is the balance of the
    /// whole spectrum.
    private var weight = [Float](repeating: 0, count: ChladniPlate.modes.count)

    private let audio: ShaderAudio
    private var spec = [Float](repeating: 0, count: ShaderAudio.width)

    /// Per grain: how well the plate can aim it. Spread around one, with a light tail
    /// that never settles.
    private var light: [Float]
    private var roll: Roll

    /// Which half of the sand moves this frame.
    private var phase = 0

    /// Where every grain is, in plate coordinates: -1 to 1 on both axes. This is
    /// what a caller draws.
    public private(set) var grains: [SIMD2<Float>]

    /// How hard the plate is being sounded, 0 at silence. Zero means the sand does not move
    /// at all. That is intended behaviour, not an optimisation.
    public private(set) var drive: Float = 0

    /// - Parameters:
    ///   - grains: how much sand. The desktop uses sixty thousand grains; a phone uses
    ///     half, for two reasons: the grains are stepped on the thread that also owns the
    ///     window, and a plate five inches across has no room to show sixty thousand of
    ///     anything.
    ///   - frameSize: samples an analysis frame, matching whatever supplies them.
    ///   - seed: fixed by default, so the same plate is thrown the same way every run.
    public init(grains count: Int = 30_000, frameSize: Int = 2048, seed: UInt64 = 20_260_726) {
        precondition(count >= 1, "a plate has sand on it")

        grains = [SIMD2<Float>](repeating: .zero, count: count)
        light = [Float](repeating: 1, count: count)
        roll = Roll(seed: seed)
        audio = ShaderAudio(frameSize: frameSize)

        let span = Self.modes.count * 2 * Self.table
        cosine = [Float](repeating: 0, count: span)
        sine = [Float](repeating: 0, count: span)

        buildTheTables()
        throwTheSand()
    }

    /// Samples every mode's cos and sin across the plate, once. The modes are fixed whole
    /// numbers, so this is the only trigonometry the plate ever does.
    private func buildTheTables() {
        for m in Self.modes.indices {
            for axis in 0..<2 {
                let k = Float(axis == 0 ? Self.modes[m].n : Self.modes[m].m) * .pi
                let at = (m * 2 + axis) * Self.table

                for i in 0..<Self.table {
                    let x = Float(i) / Float(Self.table - 1) * 2 - 1
                    cosine[at + i] = cos(k * x)
                    sine[at + i] = sin(k * x)
                }
            }
        }
    }

    /// Sand thrown on the plate once, by hand. It is never re-thrown: wherever the music
    /// leaves the grains is where the next passage starts from.
    private func throwTheSand() {
        // Sand is scattered by hand, not spread with a rule: it lands thicker in some
        // places than others, and that unevenness never fully washes out. It is why one
        // arm of a figure ends up heavier than the arm mirroring it. A perfectly uniform
        // pour gives a printed-looking plate.
        let tiltX = roll.unit() * 2 - 1
        let tiltY = roll.unit() * 2 - 1
        let swirl = roll.unit() * 2 * .pi

        for i in grains.indices {
            var x = 0.0, y = 0.0

            while true {
                x = roll.unit() * 2 - 1
                y = roll.unit() * 2 - 1

                // Rejection sampling against a gentle, low-frequency density: a slope
                // across the plate and one soft heap somewhere on it.
                let d = 0.62 + 0.20 * (x * tiltX + y * tiltY)
                      + 0.18 * cos(x * 2.1 + swirl) * cos(y * 1.7 - swirl)

                if roll.unit() < d { break }
            }

            grains[i] = SIMD2(Float(x), Float(y))

            // Grains are not identical. Most differ a little in how well the plate can aim
            // them, which is what makes a ridge pile unevenly instead of drawing a smooth
            // curve; two in a hundred are light enough never to settle at all, and those
            // are the dust that keeps moving.
            light[i] = roll.unit() < 0.02 ? 0.16 : 0.75 + Float(roll.unit()) * 0.55
        }
    }

    /// Takes the plate's note from the music: which modes it is sounding, and how hard.
    ///
    /// - Parameter frame: the samples being heard. Empty for silence.
    public func listen(_ frame: [Float]) {
        audio.listen(frame)

        let heard = audio.spectrum
        for i in spec.indices {
            // Rise with the note, fall like a plate ringing.
            let k: Float = heard[i] > spec[i] ? 0.40 : 0.06
            spec[i] += (heard[i] - spec[i]) * k
        }

        // Every mode is weighted by the band of the spectrum that would sound it. A song
        // with a bass line and a hi-hat sounds two modes and settles on the zeros of their
        // sum; a dense chord sounds five and draws something no other chord draws.
        var total: Float = 0

        for mi in Self.modes.indices {
            // Bands run log-spaced up the spectrum in the same order the modes do, so the
            // plate's lowest mode answers to the lowest music and its busiest to the top
            // end.
            let lo = Int(2.0 * pow(150.0, Double(mi) / Double(Self.modes.count)))
            var hi = Int(2.0 * pow(150.0, Double(mi + 1) / Double(Self.modes.count)))
            if hi <= lo { hi = lo + 1 }
            if hi > 320 { hi = 320 }

            var sum: Float = 0
            for i in lo..<hi { sum += spec[i] }

            // A knee, so a quiet mode still shapes the figure.
            let band = pow(sum / Float(hi - lo), 0.70)

            // Eased, not snapped: a plate cannot change which modes it is holding in one
            // frame, and this is what makes one figure dissolve into the next rather than
            // cut to it.
            let k: Float = band > weight[mi] ? 0.10 : 0.035
            weight[mi] += (band - weight[mi]) * k
            total += weight[mi]
        }

        // Normalised: the figure is the BALANCE between the modes. How loud the passage is
        // says how hard the sand is thrown, never what shape it makes, exactly as on a
        // real plate.
        if total > 0.0001 {
            for mi in weight.indices { weight[mi] /= total }
        }

        // Drive: how hard the plate is being hit. Fast attack, slow release, and it
        // reaches zero in silence so the sand genuinely stops rather than simmering
        // forever.
        var level: Float = 0
        for i in 2..<300 { level += spec[i] }
        level /= 298

        let want = min(1, pow(level * 3.2, 0.75))
        drive += (want - drive) * (want > drive ? 0.30 : 0.04)
        if drive < 0.004 { drive = 0 }
    }

    /// How much the plate is displaced at one point, worked out from the modes directly
    /// rather than off the tables.
    ///
    /// This is not what the sand reads (the hot loop uses the tables and needs the slope as
    /// well), but it is the same sum. A test uses it to ask the only question that matters:
    /// **did the sand actually find the lines where the plate stands still.**
    func displacement(at p: SIMD2<Float>) -> Float {
        var u: Float = 0

        for m in Self.modes.indices {
            let n = Float(Self.modes[m].n) * .pi, mm = Float(Self.modes[m].m) * .pi

            u += weight[m] * (cos(n * p.x) * cos(mm * p.y) - cos(mm * p.x) * cos(n * p.y))
        }

        return u
    }

    /// How much of each mode the plate is holding. The figure is this and nothing else.
    var sounding: [Float] { weight }

    /// One step of the sand: every grain runs downhill on the square of the plate's
    /// displacement, which is the same as saying it moves away from wherever the plate is
    /// moving and stops where it is still. The kick it gets on the way is proportional to
    /// how hard the plate is driven, so loud music scatters the figure before it re-forms
    /// and quiet music lets it sharpen.
    public func settle(_ dt: Float) {
        // Silence: the sand is left exactly where the last note put it.
        guard drive > 0, dt > 0 else { return }

        // Half the sand moves each frame, alternating, at twice the step. Thirty thousand
        // grains is a lot of work to do sixty times a second on the thread that also owns
        // the window. A grain that takes one step of 2dt instead of two of dt ends up in
        // the same place, because the motion is overdamped and the throw is random anyway.
        // The figure does not change; the cost halves.
        phase ^= 1
        let step = dt * 2

        let modes = Self.modes
        let table = Self.table
        let hop = Self.rate * step * drive
        let restless = drive * drive * 0.006 * step

        // The tables and the sand are accessed through unchecked pointers. This is not a
        // micro-optimisation: fifteen thousand grains times eight modes is over a million
        // reads a frame, and bounds checks in a debug build would make that too slow.
        cosine.withUnsafeBufferPointer { cosines in
        sine.withUnsafeBufferPointer { sines in
        light.withUnsafeBufferPointer { lights in
        weight.withUnsafeBufferPointer { weights in
        grains.withUnsafeMutableBufferPointer { sand in

            func sample(_ of: UnsafeBufferPointer<Float>, _ i: Int, _ t: Float) -> Float {
                of[i] + (of[i + 1] - of[i]) * t
            }

            var i = phase
            while i < sand.count {
                var x = sand[i].x, y = sand[i].y

                // The plate's displacement is the SUM of every mode it is holding, each
                // weighted by how much music is sounding it:
                //   u = Σ w [ cos(n π x) cos(m π y) - cos(m π x) cos(n π y) ]
                // The sand collects on the zeros of that sum, which is why the figure
                // belongs to this music and not to a mode number: change the balance of
                // the spectrum and every line moves.
                let fx = (x + 1) * 0.5 * Float(table - 1)
                let fy = (y + 1) * 0.5 * Float(table - 1)
                let ix = min(max(Int(fx), 0), table - 2)
                let iy = min(max(Int(fy), 0), table - 2)
                let tx = fx - Float(ix), ty = fy - Float(iy)

                var u: Float = 0, dux: Float = 0, duy: Float = 0

                for m in modes.indices {
                    let w = weights[m]
                    // A mode nothing is sounding costs nothing.
                    if w < 0.004 { continue }

                    let ax = m * 2 * table, bx = (m * 2 + 1) * table

                    let can = sample(cosines, ax + ix, tx), san = sample(sines, ax + ix, tx)
                    let cam = sample(cosines, ax + iy, ty), sam = sample(sines, ax + iy, ty)
                    let cbn = sample(cosines, bx + ix, tx), sbn = sample(sines, bx + ix, tx)
                    let cbm = sample(cosines, bx + iy, ty), sbm = sample(sines, bx + iy, ty)

                    let n = Float(modes[m].n) * .pi, mm = Float(modes[m].m) * .pi

                    u += w * (can * cbm - cbn * cam)
                    dux += w * (-n * san * cbm + mm * sbn * cam)
                    duy += w * (-mm * can * sbm + n * cbn * sam)
                }

                // A grain is thrown while the plate is moving under it, and it stops when
                // it lands somewhere the plate is not. Both halves matter:
                //
                //   still far from a nodal line: throw it again, a fixed distance, mostly
                //                                at random, a little of it aimed at the
                //                                quiet
                //   within a ridge of one:       the plate barely moves here. It has
                //                                arrived, and it stays.
                //
                // Nothing sorts the grains and nothing draws the figure. The sand
                // accumulates because arriving is the only absorbing state there is, and
                // it arrives at a steady rate because a hop is a fixed size: a grain twice
                // as far from a nodal line takes twice as long.
                let slope = (dux * dux + duy * duy).squareRoot() + 1e-5

                if abs(u) > Self.capture * slope {
                    let gx = u * dux, gy = u * duy
                    let g = (gx * gx + gy * gy).squareRoot() + 1e-5

                    // Aimed at the quieter plate. Only a bias on a throw that is mostly
                    // random, which is why the ridges come out soft rather than drawn.
                    x -= gx / g * hop * Self.aim * lights[i]
                    y -= gy / g * hop * Self.aim * lights[i]

                    x += roll.nudge() * hop * Self.scatter
                    y += roll.nudge() * hop * Self.scatter
                }

                // A hard-driven plate has grains hopping over the whole of it, settled
                // ridges included, so a loud passage looks restless and can knock arrived
                // sand back into play. Squared, so it belongs to loud passages only and
                // never enough to stop the figure forming.
                x += roll.nudge() * restless
                y += roll.nudge() * restless

                // The plate has edges, and sand thrown off one is simply poured back on
                // somewhere at random. Bouncing it off the rim instead would build a line
                // of grains around the border that the physics never put there.
                if x < -1 || x > 1 || y < -1 || y > 1 {
                    x = Float(roll.unit() * 2 - 1)
                    y = Float(roll.unit() * 2 - 1)
                }

                sand[i] = SIMD2(x, y)
                i += 2
            }
        }}}}}
    }
}
