import Foundation

/// The ribbon sea: fifteen contour lines of one rolling surface, seen nearly edge-on
/// through a real perspective camera, with wrinkles that are born at the left from the
/// music of the instant and travel right along each line like a wave sent down a rope.
///
/// Ported from `RPM.Core/Viz/RibbonSea.cs`, figure for figure.
///
/// This is the desktop's vertex shader, moved off the GPU. The desktop keeps it on the GPU
/// because it has real geometry. The phone apps do not, so the arithmetic below is the
/// shader's, line for line, and the app strokes the polylines that this hands back.
/// Fifteen lines of a hundred and fifty points is two thousand two hundred and fifty
/// projections a frame, which is cheap. Solving the same projection per pixel in a
/// fragment shader would be far too slow.
public final class RibbonSea {
    /// Contour lines, low band at the front.
    public static let lines = 15

    /// Points along each line's length.
    public static let columns = 150

    // The scrolling record of recent band energy that makes the wrinkles travel. Columns
    // are time with NOW at column 0, rows are frequency from bass at row 0 to treble at
    // the top. A point at u reads column u, so its amplitude is the music of one
    // travel-time ago: a crest born at the left edge flows right over the length of the
    // history.
    private static let historyColumns = 100
    private static let historyBands = 16

    private let audio: ShaderAudio
    private var spec = [Float](repeating: 0, count: ShaderAudio.width)
    private var history = [Float](repeating: 0,
                                  count: RibbonSea.historyBands * RibbonSea.historyColumns)

    private var swellNow: Float = 0
    private var swellHold: Double = 0

    /// - Parameter frameSize: samples an analysis frame, as ``ShaderAudio`` wants them.
    public init(frameSize: Int = 2048) { audio = ShaderAudio(frameSize: frameSize) }

    /// The sea's own dynamics: how high the whole swell is, 0 at rest.
    ///
    /// Fast attack, a short hold at the peak, then a slow settle. It is deliberately slow,
    /// because this is the motion of an ocean, which does not twitch. The wrinkles carry
    /// everything quick.
    public var swell: Float { swellNow }

    /// Takes a frame of played samples and moves the sea on: the spectrum is smoothed per
    /// bin, the broadband swell is enveloped, and every band pushes this instant's energy
    /// into the left column of its own history row.
    ///
    /// Called at about 40 Hz. A sea does not change within 25 ms, and the picture animates
    /// off the clock in between.
    ///
    /// - Parameters:
    ///   - frame: played samples, or empty for silence.
    ///   - now: seconds on the stage's own clock; only the swell's hold reads it.
    public func listen(_ frame: [Float], now: Double) {
        audio.listen(frame)

        let heard = audio.spectrum
        for i in spec.indices {
            // Rise fast, fall slow.
            let k: Float = heard[i] > spec[i] ? 0.35 : 0.10
            spec[i] += (heard[i] - spec[i]) * k
        }

        // The macro swell, off a wide already-smoothed band.
        let lo = 2, hi = 220
        var sum: Float = 0
        for i in lo..<hi { sum += spec[i] }
        let level = sum / Float(hi - lo)

        if level > swellNow {
            swellNow += (level - swellNow) * 0.35
            swellHold = now + 0.35
        } else if now >= swellHold {
            swellNow += (level - swellNow) * 0.010
        }

        scroll()
    }

    /// Every band's row shifts one column to the right and takes this instant's energy at
    /// the left. Bands are log-spaced, bass at row 0.
    private func scroll() {
        for band in 0..<Self.historyBands {
            let lo = Int(2.0 * pow(200.0, Double(band) / Double(Self.historyBands)))
            var hi = Int(2.0 * pow(200.0, Double(band + 1) / Double(Self.historyBands)))
            if hi <= lo { hi = lo + 1 }
            if hi > 500 { hi = 500 }

            var sum: Float = 0
            for i in lo..<hi { sum += spec[i] }

            let row = band * Self.historyColumns
            for c in stride(from: Self.historyColumns - 1, to: 0, by: -1) {
                history[row + c] = history[row + c - 1]
            }
            history[row] = min(1, max(0, sum / Float(hi - lo)))
        }
    }

    /// Projects every line into normalised device coordinates (x and y from -1 to 1, y up)
    /// for a frame of the given shape.
    ///
    /// - Parameters:
    ///   - time: seconds since the stage came up.
    ///   - aspect: the frame's height over its width. The projection is scaled by the
    ///     HEIGHT in both axes, so a wider frame is a wider window onto the same sea
    ///     rather than a stretched one.
    ///   - into: filled line by line, point by point. Reused frame to frame by the caller.
    public func trace(_ time: Double, aspect: Float, into: inout [SIMD2<Float>]) {
        precondition(into.count >= Self.lines * Self.columns,
                     "needs \(Self.lines * Self.columns) points")

        let t = Float(time)

        // Breathing: the resting amplitude swells and relaxes on two slow sines with
        // unrelated periods, and the roll's own pace varies with a third, so the sea never
        // travels at a constant rate.
        let breath = 0.60 + 0.25 * sin(t * 0.42) + 0.15 * sin(t * 0.27 + 1.3)
        let seaTime = t * 0.2 + 0.18 * sin(t * 0.33)
        let amplitude = 0.16 * breath + swellNow * 1.25

        // The camera: a pinhole raised above the sea and pitched down twenty degrees, so
        // the swell reads as height and the bands recede toward a horizon.
        let focal: Float = 2.6
        let pitch = Float(20) * .pi / 180
        let cp = cos(pitch), sp = sin(pitch)
        let dist: Float = 3.2
        let camY = dist * sp, camZ = -dist * cp

        // How much ocean a frame of this shape gets. The desktop draws into a square and
        // lets a wide window crop the sides, so its lines always leave the frame. Scaling
        // by height instead (which keeps the perspective correct) would put the line ends a
        // few per cent inside a landscape phone's edges, and a line that fades out in the
        // middle of the screen looks like the sea has run out. So a wider window is given
        // a longer stretch of sea, not a stretched one.
        let reach = max(1, 0.62 / max(aspect, 0.01))

        var k = 0
        for line in 0..<Self.lines {
            let v = Float(line) / Float(Self.lines - 1)
            let wz = (v - 0.5) * 2.2

            // Wider toward the back, or perspective pulls the far lines' ends inside the
            // frame and the end fade shows up as a black gap where the sea should carry on.
            let span = (3.0 + v * 3.4) * reach

            // The front reads treble, the back reads bass; treble small at the front, bass
            // big at the back.
            let fcoord = 1 - v
            let ramp = 0.06 + (0.15 - 0.06) * v

            for c in 0..<Self.columns {
                let u = Float(c) / Float(Self.columns - 1)
                let wx = (u - 0.5) * span

                var wy = Self.sea(wx, wz, seaTime) * amplitude

                // One coherent travelling field for every row: the same wavelength, with a
                // gentle per-row phase shift, so neighbouring crests line up into a wavefront
                // instead of crossing. Only the amplitude is per row, and it is that row's
                // band delayed by how far along the line it is.
                let born = read(u, band: fcoord)
                let carrier = sin(wx * 13.0 + wz * 1.6 - t * 6.0)
                            + sin(wx * 20.0 + wz * 2.4 - t * 8.4) * 0.5
                wy += carrier * (0.003 + born * ramp)

                let dy = wy - camY
                // Always positive: the sea is in front.
                let dz = wz - camZ
                let cy = dy * cp + dz * sp
                var cz = -dy * sp + dz * cp
                // Never behind the lens.
                if cz < 0.05 { cz = 0.05 }

                into[k] = SIMD2(wx * focal / cz * aspect, cy * focal / cz)
                k += 1
            }
        }
    }

    /// How bright a line is drawn: the front ones lead, and everything lifts when the music
    /// does. The fade at the ends of a line is not done here: it belongs to the stroke, not
    /// to the sea.
    public func brightness(_ line: Int) -> Float {
        let v = Float(min(max(line, 0), Self.lines - 1)) / Float(Self.lines - 1)

        return (0.45 + 0.55 * (1 - v)) * (0.8 + 0.5 * swellNow)
    }

    /// An open sea: three long directional rollers summed at low wavenumbers, so a line
    /// carries a couple of flowing curves rather than a field of little bumps. Zero-mean.
    private static func sea(_ x: Float, _ z: Float, _ t: Float) -> Float {
        var h: Float = 0
        h += 0.50 * sin(along(1.00, 0.30, x, z) * 1.1 - t * 0.55)
        h += 0.28 * sin(along(0.60, -0.80, x, z) * 1.9 - t * 0.85)
        h += 0.16 * sin(along(-0.35, 1.00, x, z) * 3.2 - t * 1.15)

        return h
    }

    /// The dot of a point with a normalised direction: the shader's `dot(normalize(d), p)`.
    private static func along(_ dx: Float, _ dz: Float, _ x: Float, _ z: Float) -> Float {
        let len = (dx * dx + dz * dz).squareRoot()

        return (dx / len) * x + (dz / len) * z
    }

    /// Reads the band history the way the shader sampled its texture: normalised in both
    /// axes, linearly filtered, clamped at the edges.
    ///
    /// Not private, so that the tests can call it: the delay line is what the whole look
    /// depends on, and reading it is how that can be checked without a screen.
    func read(_ u: Float, band: Float) -> Float {
        let fx = min(max(u, 0), 1) * Float(Self.historyColumns - 1)
        let fy = min(max(band, 0), 1) * Float(Self.historyBands - 1)

        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(x0 + 1, Self.historyColumns - 1)
        let y1 = min(y0 + 1, Self.historyBands - 1)
        let tx = fx - Float(x0), ty = fy - Float(y0)

        let a = history[y0 * Self.historyColumns + x0]
        let b = history[y0 * Self.historyColumns + x1]
        let c = history[y1 * Self.historyColumns + x0]
        let d = history[y1 * Self.historyColumns + x1]

        return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty
    }
}
