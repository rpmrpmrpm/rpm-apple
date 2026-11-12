import Foundation

/// How lit each letter of the sung line is, for karaoke. It is the desktop's Pegasus sweep, as the
/// Android TV app ports it (`KaraokeLight` in its `core`), so a line lights the same on every screen.
///
/// The light moves through a word letter by letter, instead of switching the whole word on: a word
/// lit as one thing pops, and a word lit a letter at a time reads as a wipe passing over it. A word's
/// time is shared evenly between its letters, but never slower than ``slowestGlyph`` a letter,
/// because a measured word can carry a gap where the aligner lost the thread. Each letter arrives
/// over ``glyphSoftness`` or its own share, whichever is longer, so three or four letters are always
/// part lit and the eye sees one soft edge. The arrival finishes on the letter's moment, so the
/// letter is at full strength as it is sung. A held word (longer than its letters take to sing) is
/// swept slowly over the whole time it is held, at most ``heldGlyph`` a letter.
///
/// Letters are counted in reading order over the spans. The gaps between words are not counted
/// (``letters(_:)``).
public enum KaraokeLight {
    /// How strong a letter is before the light reaches it. Fainter than the lit letters, so the eye
    /// can see where the voice is, but readable, so a reader can read ahead.
    public static let rest = 0.42

    /// The shortest time the light takes to arrive at one letter, in seconds: the softness of the
    /// edge.
    public static let glyphSoftness = 0.20

    /// The slowest the light may cross a letter, in seconds: the seven letters a second that
    /// ``LyricTiming`` caps a line at.
    public static let slowestGlyph = 1.0 / 7.0

    /// The slowest the light may cross a letter of a held word, in seconds.
    public static let heldGlyph = 0.6

    /// The shortest time a word is swept over, in seconds. A measured word can be a sliver at the end
    /// of a pause. Such a word borrows time from the pause before it, so it eases in and still ends
    /// on its own moment.
    public static let shortestWord = 0.5

    /// The slowest the light may cross a letter of a line's last word, in seconds. A note is often
    /// held on the last word, and a measurement often catches only its end. The word is swept from
    /// where the word before it ended, through the whole hold.
    public static let lastGlyph = 1.5

    /// How long a sung line takes to fade back to ``rest`` after its last word, in seconds.
    public static let lineFade = 1.5

    /// How many letters the spans hold.
    public static func letters(_ spans: [WordSpan]) -> Int {
        spans.reduce(0) { $0 + $1.length }
    }

    /// How far the light has arrived at letter `letter` of `word` at `now`, from 0 (not yet) to 1
    /// (lit). `last` is whether the word ends the line, the only place a word is taken as a held
    /// note. `earliest` is where the word before it ended: a short word may start early, into the
    /// pause before it, but not before that.
    public static func through(_ word: WordSpan, letter: Int, last: Bool, now: Double,
                               earliest: Double) -> Double {
        let count = word.length
        let shortest = max(shortestWord, Double(count) * slowestGlyph)

        let from: Double
        if last {
            from = max(earliest, min(word.from, word.to - Double(count) * lastGlyph))
        } else if word.to - word.from >= shortest {
            from = word.from
        } else {
            from = max(earliest, min(word.from, word.to - shortest))
        }

        let held = word.to - from
        let share = held / Double(max(1, count))
        // A word sung in its letters' time keeps the cap. A held word is swept over its hold.
        let step = share > slowestGlyph ? min(share, last ? lastGlyph : heldGlyph) : share
        let opens = from + step * Double(letter)
        let arriving = max(glyphSoftness, step)
        return min(max((now - (opens - arriving)) / arriving, 0), 1)
    }

    /// The strength of every letter at `now`, from ``rest`` to 1, in reading order.
    ///
    /// With `fades`, the line goes back to rest after its last word (``lineFade``). Without it, the
    /// line stays lit. The line being sung does not fade: faded back after its last word, it stood
    /// grey through every pause before the next line.
    public static func light(_ spans: [WordSpan], now: Double, fades: Bool) -> [Double] {
        let after = spans.isEmpty || !fades ? 0 : now - spans[spans.count - 1].to
        let fade: Double
        if after <= 0 {
            fade = 1
        } else {
            let t = min(max(after / lineFade, 0), 1)
            fade = 1 - t * t * (3 - 2 * t)
        }

        var strengths: [Double] = []
        strengths.reserveCapacity(letters(spans))

        for (index, word) in spans.enumerated() {
            let last = index == spans.count - 1
            // The first word may not reach back before the line's own first moment.
            let earliest = index == 0 ? word.from : spans[index - 1].to
            for letter in 0..<word.length {
                let lit = through(word, letter: letter, last: last, now: now, earliest: earliest)
                strengths.append(rest + (1 - rest) * lit * fade)
            }
        }

        return strengths
    }

    /// How strong the line reads as a whole at `now`: the mean of its letters' strengths. One with
    /// no letters reads as fully lit.
    public static func overall(_ spans: [WordSpan], now: Double, fades: Bool) -> Double {
        let strengths = light(spans, now: now, fades: fades)
        guard !strengths.isEmpty else { return 1 }
        return strengths.reduce(0, +) / Double(strengths.count)
    }
}

/// Which words of the score are lit when, for karaoke: the measured words a line takes, and the line
/// that is shown while the last one is still being sung. The rules of the Android TV app's lyric
/// column.
public enum KaraokeLines {
    /// How far before its stamp a line's last measured word may end and still be taken, in seconds.
    static let stray = 1.0

    /// How long before its first measured word a line takes over, in seconds: about when the light
    /// starts to arrive.
    static let lead = 0.35

    /// The longest a line waits past its stamp for its first measured word, in seconds.
    static let waitLongest = 4.0

    /// The measured words of the line `text` at `seconds`, where they fall in the line's own time:
    /// none may end before the line starts (with ``stray`` of slack), and the first may not start
    /// after the next piece does (`next`). Words placed outside that are the aligner's mistake, and
    /// the line is then swept by length instead.
    public static func heard(_ measured: [MeasuredLine], text: String, seconds: Double,
                             next: Double) -> [WordSpan]? {
        guard let words = MeasuredLyrics.forLine(measured, text: text, seconds: seconds),
              let first = words.first, let last = words.last
        else { return nil }

        if last.to < seconds - stray { return nil }
        if next.isFinite && first.from > next { return nil }
        return words
    }

    /// Each piece's measured words, by the piece's place in the score. Nil for a rest and for a
    /// line with no measured words that fit.
    public static func heard(_ score: LyricScore, measured: [MeasuredLine]) -> [[WordSpan]?] {
        score.parts.map { part in
            guard case .words(let line) = part.piece else { return nil }
            return heard(measured, text: line.text, seconds: line.seconds, next: next(after: part, in: score))
        }
    }

    /// The spans the sung line is lit by: its measured words where they fit, else the line's time
    /// shared between its words by length.
    public static func spans(of part: LyricScore.Part, in score: LyricScore,
                             heard: [[WordSpan]?]) -> [WordSpan] {
        guard case .words(let line) = part.piece else { return [] }
        if heard.indices.contains(part.id), let measured = heard[part.id] { return measured }
        return LyricTiming.sweep(line.text, from: line.seconds, until: next(after: part, in: score))
    }

    /// When the piece after `part` starts, or infinity after the last piece.
    public static func next(after part: LyricScore.Part, in score: LyricScore) -> Double {
        let after = part.id + 1
        return score.parts.indices.contains(after) ? score.parts[after].seconds : .infinity
    }

    /// The piece to show at `seconds`, given the piece that the time stamps say.
    ///
    /// It is the previous piece while that piece's measured words are still being sung and the
    /// words of `piece` have not started. A stamp often comes before the last word of the line
    /// before it, and moving on at the stamp would leave that word unlit.
    ///
    /// It is also the previous piece while the measured words of `piece` are still well ahead. A
    /// line measured to start well after its stamp would stand there unlit until the voice reaches
    /// it. That wait is never longer than ``waitLongest`` past the stamp, so a measurement that went
    /// wrong cannot hold the lyrics back.
    public static func held(_ score: LyricScore, piece: Int?, seconds: Double,
                            heard: [[WordSpan]?]) -> Int? {
        guard let piece, heard.indices.contains(piece), score.parts.indices.contains(piece)
        else { return piece }

        // Before the first piece is nil: the intro is shown.
        let before = piece >= 1 ? piece - 1 : nil
        let starts = heard[piece]?.first?.from

        if let before, let last = heard[before]?.last, last.to > seconds {
            if let starts, starts <= seconds { return piece }
            return before
        }

        let stamp = score.parts[piece].seconds
        if let starts, seconds < starts - lead, seconds < stamp + waitLongest { return before }
        return piece
    }
}
