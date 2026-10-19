import Foundation

/// The colour of a cover.
///
/// The colour is taken from a 48 by 48 pixel copy of the cover, not from the full picture.
/// A cover is about a megabyte of pixels, and the answer is one colour. Reading every pixel
/// does far more work than the question needs. At 48 pixels the copy is cheap to read, and a
/// thin, vivid stripe still survives the downscale.
///
/// The caller does the downscaling. On iOS that is ImageIO's job. Doing it here would add a
/// framework to code that needs none.
public enum CoverColor {
    /// The colour to tint a surface beside this cover with: its ``highlight``, or its
    /// ``dominant`` where the cover has no vivid colour at all.
    ///
    /// The highlight is tried first. A tint should show what the record looks like. The accent
    /// of a cover is a better guide to that than the brown or grey that most of the cover is
    /// made of.
    public static func tint(rgba: [UInt8]) -> RGB? {
        highlight(rgba: rgba) ?? dominant(rgba: rgba)
    }

    /// Coarse buckets: 8 levels per channel, so near-identical pixels count together. A
    /// photograph then does not produce a thousand shades of one colour.
    private static func key(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
        // Parenthesised on purpose. C# reads `r >> 5 << 10` from left to right. Swift does not
        // guess at that order and reports the unparenthesised form as ambiguous.
        (((Int(r) >> 5) << 10) | ((Int(g) >> 5) << 5) | (Int(b) >> 5))
    }

    private struct Bucket { var count = 0; var r = 0; var g = 0; var b = 0 }

    private static func average(_ bucket: Bucket) -> RGB {
        RGB(UInt8(clamping: bucket.r / bucket.count),
            UInt8(clamping: bucket.g / bucket.count),
            UInt8(clamping: bucket.b / bucket.count))
    }

    /// The colour most of the cover is, or nil when it has none to give.
    ///
    /// Near-black and near-white are skipped. A cover is often mostly one of them. "This record
    /// is black" is true of many records, and it tells you little about any of them.
    ///
    /// A tie goes to the bucket seen first in the pixels, as on the desktop. It does not go to
    /// the dictionary's order. Swift randomises that order for each process, so the same cover
    /// could get a different dominant colour on each launch.
    public static func dominant(rgba: [UInt8]) -> RGB? {
        var buckets: [Int: Bucket] = [:]
        var seen: [Int] = []

        for i in stride(from: 0, to: rgba.count - 3, by: 4) {
            let r = rgba[i], g = rgba[i + 1], b = rgba[i + 2]
            let hi = Swift.max(r, g, b), lo = Swift.min(r, g, b)
            if hi < 24 || lo > 232 { continue }

            let at = key(r, g, b)
            var bucket = buckets[at] ?? Bucket()
            if bucket.count == 0 { seen.append(at) }
            bucket.count += 1; bucket.r += Int(r); bucket.g += Int(g); bucket.b += Int(b)
            buckets[at] = bucket
        }

        var best: Bucket?
        for at in seen where buckets[at]!.count > (best?.count ?? 0) { best = buckets[at] }
        return best.map(average)
    }

    /// The colours a cover is actually made of, most telling first. No two of them are the
    /// same colour.
    ///
    /// This matches `CoverColor.Palette` in the desktop app. It exists for one reason. A sleeve
    /// painted with one colour and a guessed colour puts a colour on screen that is not on the
    /// record at all. If the code takes a dominant colour and a highlight, then turns a hue to
    /// make a third colour, that third colour is often invented. For example, a gold sleeve
    /// with red lettering gives gold twice. A hue about 42 degrees away from gold is green.
    ///
    /// Colours are scored as ``highlight(rgba:)`` scores them: vivid, present and bright. A
    /// small splash of real colour beats a large area of dull colour. The result is a list, not a
    /// single winner. Each new colour must differ from the colours already chosen. Distance is
    /// measured between the colours' **directions**, not their values. So a light red and a
    /// dark red count as one colour, and only one of them is returned. Brightness does not
    /// make two colours different.
    ///
    /// - Returns: up to `count` colours. There can be fewer, or none, when the cover has no
    ///   more to give.
    public static func palette(rgba: [UInt8], count: Int) -> [RGB] {
        guard count > 0 else { return [] }

        var buckets: [Int: Bucket] = [:]

        for i in stride(from: 0, to: rgba.count - 3, by: 4) {
            let r = rgba[i], g = rgba[i + 1], b = rgba[i + 2]
            let hi = Swift.max(r, g, b), lo = Swift.min(r, g, b)

            // Too dark, or too grey to be one of a cover's colours.
            if hi < 40 || Int(hi) - Int(lo) < 24 { continue }

            var bucket = buckets[key(r, g, b)] ?? Bucket()
            bucket.count += 1; bucket.r += Int(r); bucket.g += Int(g); bucket.b += Int(b)
            buckets[key(r, g, b)] = bucket
        }

        // Sorted by score. Ties are broken by the bucket key, because Swift randomises
        // dictionary order for each process. Without this, two covers with the same score
        // could pick different colours on two runs of the same library.
        let scored = buckets.keys.sorted()
            .map { (score(buckets[$0]!), average(buckets[$0]!)) }
            .sorted { $0.0 > $1.0 }

        var chosen: [RGB] = []
        for (_, colour) in scored {
            if chosen.count >= count { break }
            if !chosen.contains(where: { same($0, colour) }) { chosen.append(colour) }
        }

        return chosen
    }

    /// How much a bucket looks like a cover's colour: vivid, present and bright.
    private static func score(_ bucket: Bucket) -> Double {
        let r = Double(bucket.r) / Double(bucket.count)
        let g = Double(bucket.g) / Double(bucket.count)
        let b = Double(bucket.b) / Double(bucket.count)

        let hi = Swift.max(r, g, b), lo = Swift.min(r, g, b)
        let saturation = hi <= 0 ? 0 : (hi - lo) / hi

        return saturation * Double(bucket.count).squareRoot() * (hi / 255)
    }

    /// Whether two colours count as the same colour. They are compared as **directions**, so
    /// how light or dark each one is does not matter.
    private static func same(_ a: RGB, _ b: RGB) -> Bool {
        func unit(_ c: RGB) -> (Double, Double, Double) {
            let r = Double(c.r), g = Double(c.g), b = Double(c.b)
            let length = (r * r + g * g + b * b).squareRoot()
            return length < 1 ? (0, 0, 0) : (r / length, g / length, b / length)
        }

        let (ar, ag, ab) = unit(a), (br, bg, bb) = unit(b)
        let d = ((ar - br) * (ar - br) + (ag - bg) * (ag - bg) + (ab - bb) * (ab - bb))

        return d.squareRoot() < 0.22
    }

    /// The most vivid colour in the cover: the accent, not the muted dominant colour.
    ///
    /// The cover uses the same coarse buckets. Each bucket is scored by how saturated and
    /// bright it is, with a small weight for how many pixels it has. **So a small splash of
    /// vivid colour beats a large area of grey or brown.** The square root of the count keeps
    /// that weight small. A bucket ten times larger counts about three times as much, not ten
    /// times.
    ///
    /// Returns nil when the cover has no real colour. That is the correct answer for a black
    /// and white press photo.
    public static func highlight(rgba: [UInt8]) -> RGB? {
        var buckets: [Int: Bucket] = [:]

        for i in stride(from: 0, to: rgba.count - 3, by: 4) {
            let r = rgba[i], g = rgba[i + 1], b = rgba[i + 2]
            let hi = Swift.max(r, g, b), lo = Swift.min(r, g, b)

            // Too dark, or too grey to be a highlight.
            if hi < 40 || Int(hi) - Int(lo) < 24 { continue }

            var bucket = buckets[key(r, g, b)] ?? Bucket()
            bucket.count += 1; bucket.r += Int(r); bucket.g += Int(g); bucket.b += Int(b)
            buckets[key(r, g, b)] = bucket
        }

        guard !buckets.isEmpty else { return nil }

        var best = -1.0
        var winner: Bucket?

        // Visited in a fixed order. Swift randomises dictionary order for each process. Without
        // this, two covers with the same score could pick different colours on two runs of the
        // same library.
        for bucketKey in buckets.keys.sorted() {
            let bucket = buckets[bucketKey]!
            let scored = score(bucket)

            if scored > best { best = scored; winner = bucket }
        }

        return winner.map(average)
    }
}
