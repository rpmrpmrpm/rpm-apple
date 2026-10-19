import Foundation

/// One face of one block, placed and lit: four corners in normalised device coordinates
/// (x and y from -1 to 1, y up) and the colour of the whole face.
///
/// **A face rather than two triangles.** This is the one place where the port differs from
/// the C# code in shape rather than in figures. The desktop gives Skia a vertex buffer
/// because `DrawVertices` needs one. Nothing here does, and the colour is flat across a
/// face in both versions (every corner of a face gets the same value). So the picture is
/// the same, with half the geometry and no winding order.
public struct BlockFace: Sendable {
    public let a, b, c, d: SIMD2<Float>
    public let colour: SIMD3<Float>
}

/// A flight through a field of turning blocks, lit by the track.
///
/// Ported from `RPM.Core/Viz/BlockFlow.cs`, figure for figure.
///
/// The desktop draws this as instanced geometry: one cube mesh, with a few thousand copies
/// placed and turned in a vertex shader. The phone apps cannot do that. So the placing,
/// the turning and the lighting happen here, once per block per frame, and the app draws
/// what comes back.
///
/// The field is a lattice that scrolls with the camera: a block is never created or
/// destroyed, the lattice simply renumbers under the flight and the far row becomes the
/// near one. Everything a cell owns (its size, its height, how it spins, whether it is one
/// of the lit ones and which band lights it) is hashed from its coordinates, exactly as in
/// the shader. So a thousand blocks stay individual with no per-frame bookkeeping at all.
///
/// There are fewer blocks than the desktop's forty by sixty-four, because these corners are
/// transformed on the CPU rather than the GPU, and because a five-inch screen cannot show
/// that many blocks as anything but noise. Faces are drawn in painter's order, far row
/// first: the blocks are opaque and convex, so a depth buffer would only settle ties that
/// the lattice order already settles.
public final class BlockFlow {
    /// Lattice cells across.
    public static let columns = 20

    /// ...and ahead of the camera.
    public static let rows = 36

    /// Spacing between cells, in world units.
    private static let cell: Float = 0.62

    /// The nearest row starts this far ahead, so nothing flies through the lens.
    private static let nearSkip: Float = 1.4

    /// How fast the field fogs out. It is set from this lattice's own depth, not copied from
    /// the desktop: a density tuned for sixty-four rows would leave the last of thirty-six
    /// rows still lit, and a straight edge would show across the picture where the world
    /// stops. This puts the far row at a tenth of its brightness, as on the desktop.
    private static let fog: Float = 2.3 / (Float(BlockFlow.rows) * BlockFlow.cell)

    /// The navy everything fogs into. The app clears to this.
    public static let background = SIMD3<Float>(0.012, 0.020, 0.043)

    private let audio: ShaderAudio
    private var spec = [Float](repeating: 0, count: ShaderAudio.width)

    private var corner = [SIMD3<Float>](repeating: .zero, count: 8)
    private var screen = [SIMD2<Float>](repeating: .zero, count: 8)

    private var swellNow: Float = 0
    private var swellHold: Double = 0
    private var flownSoFar: Double = 0

    /// Every face of every block that is worth drawing, far row first. Rebuilt by
    /// ``fill(_:widthOverHeight:)`` and reused frame to frame.
    public private(set) var faces: [BlockFace] = []

    public init(frameSize: Int = 2048) {
        audio = ShaderAudio(frameSize: frameSize)
        faces.reserveCapacity(Self.columns * Self.rows * 3)
    }

    /// The broadband level, enveloped: fast attack, a held peak, a slow settle. It lifts
    /// the light, the block scale and the speed of the flight all at once.
    public var swell: Float { swellNow }

    /// How far the flight has travelled, in world units.
    public var flown: Float { Float(flownSoFar) }

    /// Takes a frame of played samples: the spectrum is smoothed per bin and the swell is
    /// enveloped. Called at about 40 Hz. The flight itself runs off the clock.
    public func listen(_ frame: [Float], now: Double) {
        audio.listen(frame)

        let heard = audio.spectrum
        for i in spec.indices {
            // Rise fast, fall slow.
            let k: Float = heard[i] > spec[i] ? 0.35 : 0.10
            spec[i] += (heard[i] - spec[i]) * k
        }

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
    }

    /// Moves the flight on. Distance is integrated rather than read off the clock, so the
    /// music can push the speed without the field jumping when it does.
    public func advance(_ seconds: Double) {
        flownSoFar += min(max(seconds, 0), 0.1) * (1.30 + Double(swellNow) * 1.10)
    }

    /// Builds the frame: every visible face of every block, placed, lit and projected.
    ///
    /// - Parameters:
    ///   - time: seconds since the stage came up.
    ///   - widthOverHeight: the frame's aspect, for the projection.
    public func fill(_ time: Double, widthOverHeight: Float) {
        faces.removeAll(keepingCapacity: true)

        let t = Float(time)
        let camZ = Float(flownSoFar)

        // The camera glides ABOVE the sheet the blocks are laid on and looks down along it,
        // so the field lies across the frame as a band with clear sky over it. The camera
        // follows the sheet's own height. Otherwise the sway would eventually drift out of
        // the band and the screen would empty. The roll puts the band on a diagonal instead
        // of flat along the horizon.
        let eyeX = sin(t * 0.13) * 1.8
        let aimX = sin(t * 0.11 + 1.3) * 2.6

        let eye = SIMD3<Float>(eyeX, Self.sheet(eyeX, camZ, t) + 0.55 + sin(t * 0.19) * 0.30, camZ)
        let aim = SIMD3<Float>(aimX, Self.sheet(aimX, camZ + 7.5, t) + 0.10, camZ + 7.5)
        let up = SIMD3<Float>(sin(t * 0.05) * 0.42, 1, 0)

        // **The camera is written out rather than built as a matrix**, and it is the same
        // camera. A right-handed look-at matrix does exactly this: the three axes below, and
        // a translation that is minus the eye projected onto each of them. A perspective
        // matrix multiplies x and y by the two scales and puts minus the view depth in w.
        // Composing them into a four by four and multiplying a row vector through it would
        // be the same eleven multiplies wrapped in forty-eight.
        let zaxis = normalise(eye - aim)
        let xaxis = normalise(cross(up, zaxis))
        let yaxis = cross(zaxis, xaxis)

        let yScale = 1 / tan(Float.pi / 3.1 * 0.5)
        let xScale = yScale / max(0.1, widthOverHeight)

        // Just above and behind the lens.
        let lamp = eye + SIMD3<Float>(0, 3.2, 2.0)

        for row in 0..<Self.rows {
            // Far row first: the blocks are opaque, so this is the painter's order that
            // keeps the field readable without a depth buffer.
            let ck = (camZ / Self.cell).rounded(.down) + Float(Self.rows - 1 - row)

            for col in 0..<Self.columns {
                let ci = Float(col) - Float(Self.columns) * 0.5 + 0.5

                let h1 = Self.hash(ci, ck)
                let h2 = Self.hash(ci + 17.31, ck + 17.31)
                let h3 = Self.hash(ci + 41.77, ck + 41.77)
                let h4 = Self.hash(ci + 73.19, ck + 73.19)

                // Jittered off the lattice, or flying down it shows up as rows and columns.
                let cx = (ci + (h3 - 0.5) * 0.55) * Self.cell
                let cz = (ck + (h4 - 0.5) * 0.55) * Self.cell + Self.nearSkip

                // Height: the blocks drift around a slowly rolling sheet rather than
                // filling a box. This makes the field look like a band that the camera
                // flies THROUGH: blocks pass above and below as well as on either side.
                let cy = (h2 - 0.5) * 1.5 + Self.sheet(cx, cz, t)

                let centre = SIMD3<Float>(cx, cy, cz)

                let size = (0.05 + h1 * 0.22) * (1.0 + swellNow * 0.30)
                let a1 = t * (0.35 + h3 * 0.55) + h1 * 2 * .pi
                let a2 = t * (0.28 + h4 * 0.45) + h2 * 2 * .pi

                let s1 = sin(a1), c1 = cos(a1)
                let s2 = sin(a2), c2 = cos(a2)

                // The eight corners, spun and placed, then projected once each: a cube's
                // faces share them, and projecting per face would do the same arithmetic
                // three times over.
                var anyBehind = false

                for i in 0..<8 {
                    let p = Self.spin(Self.cube[i] * size, s1, c1, s2, c2) + centre
                    corner[i] = p

                    let from = p - eye
                    let w = -simd_dot(from, zaxis)

                    // A block straddling the lens is dropped, not clipped.
                    if w <= 0.001 { anyBehind = true; break }

                    screen[i] = SIMD2(simd_dot(from, xaxis) * xScale / w,
                                      simd_dot(from, yaxis) * yScale / w)
                }

                if anyBehind { continue }

                // A minority of blocks burn rather than reflect, each on its own band, so a
                // bright top end sets a different part of the field alight than a bass line
                // does.
                var glow: Float = 0
                if h4 >= 0.78 {
                    let where_ = Self.frac(h3 * 0.8 + t * 0.01) * 0.55 + 0.02
                    glow = pow(band(at: where_), 2.2) * 1.9
                }

                let tint = mix(SIMD3<Float>(0.05, 0.26, 0.62), SIMD3<Float>(0.03, 0.15, 0.42), h1)

                for f in 0..<6 {
                    let normal = Self.spin(Self.faceNormals[f], s1, c1, s2, c2)
                    let quad = Self.quads[f]

                    let world = (corner[quad.0] + corner[quad.1]
                               + corner[quad.2] + corner[quad.3]) * 0.25

                    let toCam = eye - world
                    // Facing away.
                    if simd_dot(normal, toCam) <= 0 { continue }

                    // The vignette, at the face's own place on the screen. The desktop's
                    // fragment shader applies it per pixel; a block is a few points across,
                    // so per face is the same picture.
                    let mid = (screen[quad.0] + screen[quad.1]
                             + screen[quad.2] + screen[quad.3]) * 0.25

                    let lit = shade(tint, normal: normal, world: world, toCam: toCam,
                                    lamp: lamp, glow: glow, vignette: Self.vignette(mid))

                    faces.append(BlockFace(a: screen[quad.0], b: screen[quad.1],
                                           c: screen[quad.2], d: screen[quad.3], colour: lit))
                }
            }
        }
    }

    /// One lamp sits just above and behind the camera, so the field lights up as the camera
    /// flies into it and falls dark behind. That gives the sense of travelling through it.
    /// The result then fogs into the navy background so the lattice has no visible far edge.
    private func shade(_ tint: SIMD3<Float>, normal: SIMD3<Float>, world: SIMD3<Float>,
                       toCam: SIMD3<Float>, lamp: SIMD3<Float>,
                       glow: Float, vignette: Float) -> SIMD3<Float> {
        let dist = length(toCam)
        let n = normalise(normal)
        let view = toCam / max(dist, 0.001)
        let light = normalise(lamp - world)

        let diffuse = max(simd_dot(n, light), 0)
        let reflected = -light - 2 * simd_dot(-light, n) * n
        let specular = Self.pow26(max(simd_dot(reflected, view), 0))
        let atten = 5.5 / (1 + dist * 0.28 + dist * dist * 0.045)

        var col = tint * (0.12 + diffuse * (0.85 + swellNow * 0.6)) * atten
        col += SIMD3<Float>(0.75, 0.90, 1.0) * (specular * atten * 0.45)
        col += SIMD3<Float>(1.0, 0.58, 0.10) * (glow * min(1.4, max(0.25, atten)))

        return mix(Self.background, col, exp(-dist * Self.fog)) * vignette
    }

    /// How much of the light reaches a given place on the screen. The shape matches the
    /// desktop's: it brightens the middle as much as it darkens the corners.
    private static func vignette(_ ndc: SIMD2<Float>) -> Float {
        let u = ndc.x * 0.5 + 0.5
        let v = ndc.y * 0.5 + 0.5

        return min(1.8, max(0, u * (1 - u) * v * (1 - v) * 32 * 0.75 + 0.25))
    }

    /// The specular exponent by repeated squaring: x²⁶ is x¹⁶·x⁸·x², which is five
    /// multiplies against a transcendental called two thousand times a frame.
    private static func pow26(_ x: Float) -> Float {
        let x2 = x * x
        let x4 = x2 * x2
        let x8 = x4 * x4

        return x8 * x8 * x8 * x2
    }

    /// Spin about Y, then tumble about X: the shader's two rotations, in its order.
    private static func spin(_ p: SIMD3<Float>, _ s1: Float, _ c1: Float,
                             _ s2: Float, _ c2: Float) -> SIMD3<Float> {
        let a = SIMD3<Float>(p.x * c1 - p.z * s1, p.y, p.x * s1 + p.z * c1)

        return SIMD3(a.x, a.y * c2 - a.z * s2, a.y * s2 + a.z * c2)
    }

    /// The rolling sheet the blocks are laid on, and the height the camera follows.
    private static func sheet(_ x: Float, _ z: Float, _ t: Float) -> Float {
        sin(z * 0.35 + t * 0.30) * 0.85 + sin(x * 0.42 - t * 0.13) * 0.65
    }

    /// The spectrum at a normalised position, as the shader's texture read would give it.
    private func band(at where_: Float) -> Float {
        spec[Int(min(1, max(0, where_)) * Float(ShaderAudio.width - 1))]
    }

    /// GLSL's one-liner hash, kept identical so a cell owns the same size, spin and band it
    /// owns on the desktop.
    private static func hash(_ x: Float, _ y: Float) -> Float {
        frac(sin(x * 127.1 + y * 311.7) * 43758.5453)
    }

    private static func frac(_ v: Float) -> Float { v - v.rounded(.down) }

    private static let cube: [SIMD3<Float>] = [
        SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, -0.5),
        SIMD3(-0.5, -0.5, 0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, 0.5),
    ]

    private static let quads: [(Int, Int, Int, Int)] = [
        (4, 5, 6, 7),   // front
        (1, 0, 3, 2),   // back
        (5, 1, 2, 6),   // right
        (0, 4, 7, 3),   // left
        (7, 6, 2, 3),   // top
        (0, 1, 5, 4),   // bottom
    ]

    private static let faceNormals: [SIMD3<Float>] = [
        SIMD3(0, 0, 1), SIMD3(0, 0, -1), SIMD3(1, 0, 0),
        SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0),
    ]
}

// ── the small vector arithmetic, written out ──

private func normalise(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let n = length(v)

    return n > 1e-6 ? v / n : .zero
}

private func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func simd_dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}
