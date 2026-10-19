import Foundation

/// The arithmetic behind every visualiser: a window, a transform, and a fold into
/// log-spaced levels.
///
/// Ported from `RPM.Core/Audio/Spectrum.cs`, and kept as free of everything else as
/// that one is. **It is the only part of a stage that can be proved right.** A drawn
/// backdrop is a matter of taste and can only be looked at; a band level is a number,
/// and a tone at a known frequency belongs in a known band whatever the screen is
/// doing. So this has no audio in it, no views and no phone, and the tests put a sine
/// wave in and check where it comes out.
public enum Spectrum {

    // ── the window ──

    /// A Hann window, which is what stops a tone smearing across its neighbours.
    ///
    /// A transform assumes the window repeats for ever, so a frame that does not end
    /// where it began has a step in it, and a step is broadband: the tone arrives in
    /// every band at once. Tapering both ends to nothing is what removes it. Coherent
    /// gain 0.5, which is corrected for in ``bands(re:im:count:rate:)``.
    public static func hann(_ n: Int) -> [Float] {
        precondition(n >= 2, "a window of one sample has no shape")

        return (0..<n).map { Float(0.5 * (1 - cos(2 * Double.pi * Double($0) / Double(n - 1)))) }
    }

    // ── the transform ──

    /// An in-place radix-2 Cooley-Tukey FFT. The length must be a power of two.
    ///
    /// Written out rather than taken from Accelerate on purpose: it is the same
    /// arithmetic as the C#, so the two apps can be checked against each other, and
    /// the cost at these sizes is not what a phone notices. Accelerate is the obvious
    /// change to make if a stage ever runs short of a frame, and the tests here are
    /// what would let somebody make it safely.
    public static func transform(_ re: inout [Double], _ im: inout [Double]) {
        precondition(re.count == im.count, "the two halves must be the same length")

        let n = re.count
        precondition(n >= 2 && n & (n - 1) == 0, "the length must be a power of two")

        // Bit-reversal: the butterflies below want the input in that order.
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit

            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }

        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let wr = cos(angle), wi = sin(angle)

            var i = 0
            while i < n {
                var cr = 1.0, ci = 0.0

                for k in 0..<(length / 2) {
                    let a = i + k, b = i + k + length / 2

                    let xr = re[b] * cr - im[b] * ci
                    let xi = re[b] * ci + im[b] * cr

                    re[b] = re[a] - xr
                    im[b] = im[a] - xi
                    re[a] += xr
                    im[a] += xi

                    let ncr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = ncr
                }

                i += length
            }

            length <<= 1
        }
    }

    // ── the fold ──

    /// The lowest and highest frequency the bands cover. Below forty is a rumble
    /// nothing on a phone reproduces; above sixteen thousand is a hiss most people
    /// cannot hear and every band of it would be empty on a lossy file.
    public static let lowest = 40.0
    public static let highest = 16_000.0

    /// Folds a transformed frame into `count` log-spaced levels, 0 to 1.
    ///
    /// **Log-spaced because hearing is.** An octave is a doubling wherever it sits, so
    /// linear bands give half the display to the top octave and a sliver to the bass,
    /// which is exactly backwards from what music does.
    ///
    /// Magnitudes are normalised to amplitude: 4/N, being 2/N for the transform and
    /// twice that for the Hann window's half coherent gain. So a full-scale tone reads
    /// about 0 dBFS. A window of about -64 to +12 dBFS is mapped onto 0 to 1, which leaves
    /// headroom so ordinary music does not sit pinned at the top.
    public static func bands(re: [Double], im: [Double], count: Int, rate: Int) -> [Float] {
        precondition(count >= 1, "a spectrum of no bands is not one")
        precondition(re.count == im.count, "the two halves must be the same length")

        let n = re.count
        let perBin = Double(rate) / Double(n)
        let norm = 4.0 / Double(n)

        return (0..<count).map { band in
            let from = lowest * pow(highest / lowest, Double(band) / Double(count))
            let upto = lowest * pow(highest / lowest, Double(band + 1) / Double(count))

            // The first bin is direct current and belongs to nobody.
            let first = max(1, Int(from / perBin))
            var last = min(n / 2, Int(upto / perBin))
            if last <= first { last = first + 1 }

            guard first < n / 2 else { return 0 }

            var sum = 0.0
            var at = first
            while at < last, at < n / 2 {
                sum += (re[at] * re[at] + im[at] * im[at]).squareRoot()
                at += 1
            }

            let average = sum / Double(last - first) * norm

            // A slight lift towards the top, because music has less energy up there and
            // a display that shows that exactly is a display where nothing moves.
            let db = 20 * log10(average + 1e-6) + Double(band) * 0.18

            return Float(min(1, max(0, (db + 64) / 76)))
        }
    }

    // ── the whole of it, in one call ──

    /// Windows, transforms and folds one frame of samples.
    ///
    /// The frame is taken as it comes and must be a power of two long: it is a window
    /// of what has just been heard, and whoever holds the sound decides how much.
    public static func levels(of frame: [Float], bands count: Int, rate: Int,
                              window: [Float]? = nil) -> [Float] {
        let n = frame.count
        precondition(n >= 2 && n & (n - 1) == 0, "the frame must be a power of two")

        let shape = window ?? hann(n)
        precondition(shape.count == n, "the window and the frame must be the same length")

        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)

        for at in 0..<n { re[at] = Double(frame[at] * shape[at]) }

        transform(&re, &im)
        return bands(re: re, im: im, count: count, rate: rate)
    }
}
