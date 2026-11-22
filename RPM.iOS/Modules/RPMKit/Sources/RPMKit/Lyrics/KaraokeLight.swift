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
/// column, with the Android phone's early hand-over (`KaraokeLines` in its `core`): a line also
/// takes over before its stamp when its measured words start earlier (``held(_:piece:seconds:heard:)``).
/// The Apple TV's `LyricColumn` has its own, older rule.
public enum KaraokeLines {
    /// How far before its stamp a line's last measured word may end and still be taken, in seconds.
    static let stray = 1.0

    /// How long before its first measured word a line takes over, in seconds: about when the light
    /// starts to arrive.
    static let lead = 0.35

    /// The longest a line waits past its stamp for its first measured word, in seconds.
    static let waitLongest = 4.0

    /// The earliest before its stamp a line takes over for its first measured word, in seconds.
    static let earliest = 1.0

    /// The shortest time a line of words is the sung line, in seconds, unless the playhead is moved
    /// past it (``handovers(_:heard:)``).
    static let shortest = 1.0

    /// How finely the rules are followed through the song when the hand-overs are worked out, in
    /// seconds.
    private static let step = 0.01

    /// How long an unmeasured backing line stays up after its words are shared out, at most, in
    /// seconds. Its last word is often held, and shared out at singing speed it would go too soon.
    static let asideHeld = 3.0

    /// How far before the next line an unmeasured backing line goes, in seconds.
    static let asideGap = 0.25

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

    /// When the piece after `part` starts, or its first backing line (``LyricScore/Aside``) where
    /// that is sooner; infinity after the last piece.
    public static func next(after part: LyricScore.Part, in score: LyricScore) -> Double {
        let after = part.id + 1
        let following = score.parts.indices.contains(after) ? score.parts[after].seconds : .infinity
        guard let aside = part.asides.first else { return following }
        return min(following, aside.line.seconds)
    }

    /// When a backing line is shown and how its words are lit: `spans` over its text, shown from
    /// `from` until `until`.
    public struct Voice: Sendable, Equatable {
        public let spans: [WordSpan]
        public let from: Double
        public let until: Double

        public init(spans: [WordSpan], from: Double, until: Double) {
            self.spans = spans; self.from = from; self.until = until
        }
    }

    /// When the backing line `aside` is shown under its line, and its words.
    ///
    /// With measured words that fit it, it comes in ``lead`` before its first word, as a line does
    /// (``held(_:piece:seconds:heard:)``), but no earlier than ``earliest`` before its stamp, and it
    /// goes when its last word ends. Without them it comes in at its stamp, with its time shared
    /// between its words by length, and stays while its last word may still be held: up to
    /// ``asideHeld`` longer, and ``asideGap`` before the line after it.
    public static func voice(_ aside: LyricScore.Aside, measured: [MeasuredLine]) -> Voice {
        let line = aside.line
        if let words = heard(measured, text: line.text, seconds: line.seconds, next: aside.until),
           let first = words.first, let last = words.last {
            return Voice(spans: words, from: max(first.from - lead, line.seconds - earliest),
                         until: last.to)
        }

        let swept = LyricTiming.sweep(line.text, from: line.seconds, until: aside.until)
        let sung = swept.last?.to ?? line.seconds
        let stays = min(aside.until - asideGap, sung + asideHeld)
        return Voice(spans: swept, from: line.seconds, until: max(sung, stays))
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
    ///
    /// And it is the next piece once that piece's first measured word is ``lead`` away, even before
    /// its stamp. A sheet's stamp is often a little after the voice starts the line, by up to half a
    /// second in quick singing. Waiting for the stamp would show the line late, with its first words
    /// already sung and lit all at once. It moves on no earlier than ``earliest`` before the stamp,
    /// and not while the line it leaves is still on its last measured word, unless the next line's
    /// first word has already started.
    ///
    /// These are the rules alone. A screen asks ``handovers(_:heard:)``, which also gives every
    /// line a moment of its own.
    public static func held(_ score: LyricScore, piece: Int?, seconds: Double,
                            heard: [[WordSpan]?]) -> Int? {
        let stays = heldBack(score, piece: piece, seconds: seconds, heard: heard)
        if stays != piece { return stays }

        let next = (piece ?? -1) + 1
        guard heard.indices.contains(next), score.parts.indices.contains(next),
              let starts = heard[next]?.first?.from
        else { return piece }

        if seconds < starts - lead || seconds < score.parts[next].seconds - earliest { return piece }
        if let piece, heard.indices.contains(piece), let singing = heard[piece]?.last,
           singing.to > seconds, starts > seconds {
            return piece
        }
        return next
    }

    /// When each piece of a score takes over as the sung piece (``handovers(_:heard:)``).
    public struct Handovers: Sendable, Equatable {
        let at: [Double]

        /// The piece to show at `seconds`, or nil before the first.
        public func piece(at seconds: Double) -> Int? {
            var low = 0, high = at.count - 1
            var found: Int?
            while low <= high {
                let mid = (low + high) / 2
                if at[mid] <= seconds {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return found
        }

        /// When the next piece after `seconds` takes over, or nil when none does.
        public func next(after seconds: Double) -> Double? {
            at.first { $0 > seconds && $0.isFinite }
        }
    }

    /// When each piece of `score` takes over as the sung piece: the rules of
    /// ``held(_:piece:seconds:heard:)``, and then every line of words is the sung line for at least
    /// ``shortest``. The Android apps' `KaraokeLines.handovers`.
    ///
    /// A sheet can stamp a line a quarter of a second before the next, and the measured words of
    /// the line before can run up to the next one's. In JT's "Oh", for one, the rules alone hold
    /// "You get these beautiful crystal slippers, baby" through its last measured word and then move
    /// straight on to the line after the next: the line in between is never lit. So the moments are
    /// worked out by following the rules through the song, and the pieces after a line that would be
    /// passed over move on later. A seek still lands wherever it lands.
    ///
    /// The last answer is kept, so a view can ask on every pass for the same score and words.
    public static func handovers(_ score: LyricScore, heard: [[WordSpan]?]) -> Handovers {
        made.handovers(score, heard: heard) { workOut(score, heard: heard) }
    }

    private static let made = MadeHandovers()

    private static func workOut(_ score: LyricScore, heard: [[WordSpan]?]) -> Handovers {
        let parts = score.parts
        var at = [Double](repeating: .infinity, count: parts.count)
        guard let lastPart = parts.last else { return Handovers(at: at) }
        func rule(_ seconds: Double) -> Int {
            held(score, piece: score.index(at: seconds), seconds: seconds, heard: heard) ?? -1
        }

        // The rules are followed through the song in small steps, and each hand-over is then found
        // exactly between the last two steps. A piece the rules pass over takes over with the one
        // after it.
        let sung = heard.compactMap { $0?.last?.to }.max() ?? 0
        let end = max(lastPart.seconds, sung) + waitLongest + 1
        var reached = -1
        var before = -1.0
        var seconds = -1.0
        while seconds <= end && reached < parts.count - 1 {
            let piece = rule(seconds)
            if piece > reached {
                var low = before
                var high = seconds
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    if rule(mid) > reached { high = mid } else { low = mid }
                }
                // Stamps and measured words are given to the hundredth, so the moment is put back on
                // the microsecond it came from: a line takes over at its moment, not a hair after it.
                let round = (high * 1e6).rounded() / 1e6
                if rule(round) > reached { high = round }
                for q in (reached + 1)...piece { at[q] = high }
                reached = piece
            }
            before = seconds
            seconds += step
        }

        // Every line of words is sung for a moment: the pieces after a line that would be passed
        // over move on later.
        for p in 0..<(parts.count - 1) {
            if case .words = parts[p].piece, at[p].isFinite {
                at[p + 1] = max(at[p + 1], at[p] + shortest)
            }
        }
        return Handovers(at: at)
    }

    /// ``held(_:piece:seconds:heard:)`` without moving on early: the previous piece while it is
    /// still sung or the words of `piece` are well ahead.
    private static func heldBack(_ score: LyricScore, piece: Int?, seconds: Double,
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

/// The last hand-overs worked out (``KaraokeLines/handovers(_:heard:)``), kept for the next pass
/// over the same score and words.
fileprivate final class MadeHandovers: @unchecked Sendable {
    private let lock = NSLock()
    private var last: (score: LyricScore, heard: [[WordSpan]?], handovers: KaraokeLines.Handovers)?

    func handovers(_ score: LyricScore, heard: [[WordSpan]?],
                   workOut: () -> KaraokeLines.Handovers) -> KaraokeLines.Handovers {
        lock.lock()
        defer { lock.unlock() }
        if let last, last.score == score, last.heard == heard { return last.handovers }
        let made = workOut()
        last = (score, heard, made)
        return made
    }
}
