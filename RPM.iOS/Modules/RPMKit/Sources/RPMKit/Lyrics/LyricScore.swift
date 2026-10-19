import Foundation

/// A lyric sheet cut into what is sung and what is waited through.
///
/// **An LRC says when each line starts, and never how long it lasts.** So a break in the singing is not
/// written down. It is a gap between two lines. There are only two ways to see one: a line the writer
/// marked with no words in it, or a wait that no singing could fill. A reader sees both as the same event.
/// If only the first kind counts as a break, the screen goes blank during every instrumental that was not
/// marked.
///
/// So the sheet becomes a run of pieces: stretches of words, with a rest between them. Everything a screen
/// needs follows from that. It is worked out once per sheet, not once per line per frame. The values are
/// which stretch is being sung, whether the playhead is in a rest, and how far through that rest it is.
public struct LyricScore: Sendable, Equatable {
    /// How long a wait between two lines has to be before it counts as a break rather than a breath.
    ///
    /// The value is long, because the line on screen has just been sung and may still be sung. An LRC gives
    /// no durations, so a line is given the benefit of the doubt for a good while. Only a wait that no
    /// singing could fill is treated as a break. Twenty seconds is the desktop's own figure
    /// (`LyricHush.AfterBreak`).
    public static let rest: Double = 20

    /// How long the last line before a rest stays up, counted from its own time.
    ///
    /// **A rest does not start when the line before it starts.** An LRC gives the start of each line and
    /// never its length. So there are only two reasonable answers. The first is that the line is over at
    /// the moment the next one is due. That is right for a rest between two ordinary lines. The second, when
    /// the next line is a long way off, is an allowance for singing the line. Without this allowance the
    /// words would disappear at the moment the last line of a verse arrived, because the rest would begin at
    /// that same second.
    ///
    /// Eight seconds is a long line. It is less than half the shortest wait that counts as a break, so it can never
    /// take up a whole rest.
    public static let sung: Double = 8

    public enum Piece: Sendable, Equatable {
        case words(LyricLine)

        /// Nothing is sung between these two moments. `until` is `.infinity` after the last line, which
        /// is the correct value for a wait that never ends.
        case rest(from: Double, until: Double)

        /// Whether this is a wait rather than words.
        public var isRest: Bool {
            if case .rest = self { return true }
            return false
        }
    }

    /// One piece, with its position in the score.
    public struct Part: Sendable, Equatable, Identifiable {
        /// Its place in the score. This is the row identity a list needs. It is stable, because the score
        /// is built once per sheet.
        public let id: Int

        /// Which stretch of singing this belongs to. **A rest carries the number of the stretch it closes.**
        /// So the words before it and the rest itself are shown together, and the words after it are not.
        public let section: Int

        public let piece: Piece

        /// When this piece begins.
        public var seconds: Double {
            switch piece {
            case .words(let line): return line.seconds
            case .rest(let from, _): return from
            }
        }
    }

    public let parts: [Part]

    /// Builds the score from a sheet.
    ///
    /// A line with no words is treated as a rest, not as a piece of words. It is the writer's way of saying
    /// that the singing stops here. Drawing it as a line with no text would show nothing to the reader. The
    /// rest runs from the line's own time to the next line's time.
    public static func of(_ sheet: LyricSheet) -> LyricScore {
        var parts: [Part] = []
        var section = 0
        var lastSang: Double?

        for (at, line) in sheet.lines.enumerated() {
            let next = at + 1 < sheet.lines.count ? sheet.lines[at + 1].seconds : Double.infinity

            if LyricSheet.isWordless(line.text) {
                parts.append(Part(id: parts.count, section: section,
                                  piece: .rest(from: line.seconds, until: next)))
                section += 1
                lastSang = nil
                continue
            }

            // A wait that the writer did not mark. The rest sits between the two lines and closes the stretch
            // that ran up to it. The line after it starts the next stretch.
            if let sang = lastSang, line.seconds - sang >= rest {
                parts.append(Part(id: parts.count, section: section,
                                  piece: .rest(from: sang + sung, until: line.seconds)))
                section += 1
            }

            parts.append(Part(id: parts.count, section: section, piece: .words(line)))
            lastSang = line.seconds
        }

        // The outro. After the last line there is a wait that never ends. Without this rest, the last line
        // would stay lit for as long as the sheet is shown.
        if let sang = lastSang {
            parts.append(Part(id: parts.count, section: section,
                              piece: .rest(from: sang + sung, until: .infinity)))
        }

        return LyricScore(parts: parts)
    }

    /// Which piece the playhead is in, or nil before the first one. An intro is a real part of a song, so
    /// the score does not pretend that the first line has started.
    ///
    /// This is a binary search, because it is called once per frame.
    public func index(at seconds: Double) -> Int? {
        var low = 0, high = parts.count - 1
        var found: Int?

        while low <= high {
            let mid = (low + high) / 2
            if parts[mid].seconds <= seconds { found = mid; low = mid + 1 }
            else { high = mid - 1 }
        }

        return found
    }

    /// The stretch being sung, or nil before the first line.
    public func section(at seconds: Double) -> Int? {
        index(at: seconds).map { parts[$0].section }
    }
}
