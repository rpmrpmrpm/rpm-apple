import Foundation

/// One word of a lyric and the moment it is sung. **Only an enhanced sheet has these.** See `LyricLine.words`.
public struct LyricWord: Equatable, Sendable {
    public let seconds: Double
    public let text: String

    public init(seconds: Double, text: String) {
        self.seconds = seconds
        self.text = text
    }
}

/// One line of a lyric and the moment it is sung.
public struct LyricLine: Equatable, Sendable, Identifiable {
    public let seconds: Double
    public let text: String

    /// The line's words, each with its own time, when the sheet gives them. This is nil for an ordinary
    /// sheet, which times whole lines only.
    public let words: [LyricWord]?

    /// The place in the sheet. The time is not used as the id. A refrain that is written once and stamped
    /// four times appears four times, and two lines can share a second.
    public var id: Int { at }
    let at: Int

    public init(seconds: Double, text: String, words: [LyricWord]? = nil, at: Int = 0) {
        self.seconds = seconds
        self.text = text
        self.words = words
        self.at = at
    }
}

/// A lyric with the clock still attached. This is an LRC sheet after it has been parsed.
///
/// This follows `RPM.Core/Lyrics/LyricSheet.cs` on the desktop, rule for rule. The rules decide which stamp
/// forms are read, what the digits of a fraction mean, and which lines are kept or dropped.
///
/// **The timestamps are the whole point of a sheet.** Text with no timestamps is not a sheet. `parse` returns
/// `empty` for plain lyrics, and it does not return lines at time zero. A caller that wants something to follow
/// along with should be told clearly that there is nothing to follow.
///
/// **Blank lines are kept.** An LRC that marks an instrumental break with an empty line at 1:12 is saying that
/// nothing is sung for a while. If those lines were dropped, the verse would run into the chorus, and the
/// highlight would stay on a line that nobody is singing.
public struct LyricSheet: Equatable, Sendable {
    /// No sheet at all. This is what a track with no synced lyrics has.
    public static let empty = LyricSheet(lines: [], source: nil)

    /// The lines, in time order, earliest first.
    public let lines: [LyricLine]

    /// The LRC text this was read from, kept exactly as it arrived. Anything that stores a sheet stores what
    /// was actually sung, not this parser's reading of it.
    public let source: String?

    init(lines: [LyricLine], source: String?) {
        self.lines = lines
        self.source = source
    }

    /// Whether there is anything here worth following.
    public var isSynced: Bool { !lines.isEmpty }

    /// The line being sung at this moment, or nil before the first line. An intro is a real part of a song,
    /// so the sheet does not pretend that the first line has started.
    ///
    /// This is a binary search, because it is called once per frame.
    public func index(at seconds: Double) -> Int? {
        var low = 0, high = lines.count - 1
        var found: Int?

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].seconds <= seconds { found = mid; low = mid + 1 }
            else { high = mid - 1 }
        }

        return found
    }

    // Reading one sheet

    /// Reads an LRC sheet. Anything that is not one, such as empty text or plain lyrics with no timestamps,
    /// returns `empty`. This is not an error, and it is the common case.
    public static func parse(_ lrc: String?) -> LyricSheet {
        guard let lrc, !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }

        var lines: [LyricLine] = []
        var offset: Double = 0

        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))

            // `[offset:]` shifts the whole sheet. **The sign follows the LRC convention, not normal arithmetic.**
            // A positive offset means the words come early, so they have to be moved back.
            if let said = Self.offsetTag.firstMatch(line), let ms = Double(said) {
                offset = ms / 1000
                continue
            }

            let stamps = Self.stamp.matches(line)
            if stamps.isEmpty { continue }  // A metadata tag, or prose in a file that is not an LRC.

            // The words are whatever follows the LAST timestamp. One line can carry several timestamps,
            // which is how a refrain is written once and sung several times.
            let last = stamps[stamps.count - 1]
            let body = String(line[last.range.upperBound...])
            let text = unstamp(body)

            // The word-level stamps inside the line are read here, before `unstamp` removes them.
            // **Only for a line with ONE timestamp.** A refrain stamped four times has one set of word times.
            // That set can be correct for at most one of the four performances, and the file does not say which
            // one. A guess there puts the highlight on the wrong word in three of the four choruses. That is
            // worse than following the line alone.
            let words = stamps.count == 1 ? readWords(body, offset: offset) : nil

            for stamp in stamps {
                lines.append(LyricLine(seconds: max(0, seconds(of: stamp) - offset),
                                       text: text, words: words))
            }
        }

        guard !lines.isEmpty else { return .empty }

        // A sheet with several timestamps on one line is out of order by construction, so the lines are sorted
        // here. The index search needs them in order.
        let sorted = lines.sorted { $0.seconds < $1.seconds }

        return LyricSheet(
            lines: sorted.enumerated().map {
                LyricLine(seconds: $1.seconds, text: $1.text, words: $1.words, at: $0)
            },
            source: lrc)
    }

    /// Removes the clock from one line of lyric: the word stamps inside it, and a stamp left at its start.
    ///
    /// This is for text that will be shown on a screen. Without it, a stamp the sheet reader cannot use, such as
    /// the bare form, the round-bracket form, or the word-by-word form, would appear in the text. A reader should
    /// never see a timecode in a lyric.
    public static func unstamp(_ line: String?) -> String {
        guard let line, !line.isEmpty else { return "" }

        let spaced = Self.wordStamp.replacing(line, with: " ")
        return Self.looseStamp.replacing(spaced, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a line has nothing to read on it. That means it is empty, or it has only the note characters
    /// a writer uses to mark a break.
    ///
    /// **The parser does not use this.** The parser keeps those lines on purpose. This is for a view that
    /// decides whether a line needs a row. There are two separate questions. The sheet needs the line so the
    /// clock still has a place to land. A reader needs a row only where there are words.
    ///
    /// A note and an empty line mean the same thing. Writers use both, often in the same file: a note before
    /// the first verse, and blank lines between verses. A view that drops one kind and keeps the other leaves
    /// a gap in many songs.
    public static func isWordless(_ line: String?) -> Bool {
        guard let line, !line.trimmingCharacters(in: .whitespaces).isEmpty else { return true }

        // The four musical note characters from Miscellaneous Symbols, and the two note emoji.
        // **Sharps and flats are not included.** A lyric can be about a sharp or a flat.
        let notes: Set<Unicode.Scalar> = ["\u{2669}", "\u{266A}", "\u{266B}", "\u{266C}",
                                          "\u{1F3B5}", "\u{1F3B6}"]

        // Compare by scalar, not by character. The emoji are the reason. A character-by-character walk of a
        // surrogate pair compares half a note against a whole one, and so counts every such line as having words.
        for scalar in line.unicodeScalars where
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !notes.contains(scalar) {
            return false
        }

        return true
    }

    // The shapes a stamp can take

    /// `[mm:ss.xx]`, `[mm:ss.xxx]` and `[mm:ss]`. Some writers put a colon before the fraction, and that form
    /// is accepted too.
    private static let stamp = Pattern(#"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

    /// `[offset:+250]`. The value is in milliseconds. This is the one metadata tag that changes what is drawn.
    private static let offsetTag = Pattern(#"^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$"#)

    /// `<mm:ss.xx>`: the word stamp of an enhanced LRC. In text shown on a screen it is noise. It is also the
    /// only exact way to know which word is being sung now.
    private static let wordStamp = Pattern(#"\s*<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>\s*"#)
    private static let wordStampAt = Pattern(#"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#)

    /// A stamp written where a stamp does not belong: at the start of a line with no brackets, or inside round
    /// brackets, which some editors use. **The fraction is required for the bare form.** That is what keeps
    /// "3:15 in the morning" as a lyric and not as a timestamp.
    private static let looseStamp = Pattern(
        #"^\s*(?:\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]|\(\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\)|\d{1,3}:\d{1,2}[.:]\d{1,3})\s*"#)

    /// The time a stamp names, in seconds from the start of the recording, before any offset.
    ///
    /// **"5" is five tenths, "05" is five hundredths, and "005" is five thousandths.** The number of digits sets
    /// the scale. So a sheet with two-digit fractions and one with three-digit fractions are both read correctly.
    private static func seconds(of stamp: Pattern.Match) -> Double {
        let minutes = Double(stamp.groups[0] ?? "0") ?? 0
        let seconds = Double(stamp.groups[1] ?? "0") ?? 0

        var fraction: Double = 0
        if let said = stamp.groups[2], let value = Double(said) {
            fraction = value / pow(10, Double(said.count))
        }

        return minutes * 60 + seconds + fraction
    }

    /// The words of one enhanced line, each with its own time. This is nil for an ordinary line with no stamps
    /// inside it, which is almost every line of almost every sheet.
    ///
    /// A word is the text from its own stamp up to the next stamp, trimmed. **Text before the first stamp
    /// belongs to no word and is dropped.** Some writers put the line's opening stamp outside the brackets.
    /// Text before it was never given a time, so it is dropped.
    private static func readWords(_ body: String, offset: Double) -> [LyricWord]? {
        let stamps = wordStampAt.matches(body)
        guard !stamps.isEmpty else { return nil }

        var words: [LyricWord] = []

        for (i, stamp) in stamps.enumerated() {
            let from = stamp.range.upperBound
            let to = i + 1 < stamps.count ? stamps[i + 1].range.lowerBound : body.endIndex
            let text = String(body[from..<to]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                words.append(LyricWord(seconds: max(0, seconds(of: stamp) - offset), text: text))
            }
        }

        return words.isEmpty ? nil : words
    }
}

/// A regular expression, compiled once.
///
/// This uses `NSRegularExpression` and not Swift's own `Regex`. The same patterns are shared with the other
/// head as strings, character for character. A Swift literal would have to be rewritten in another language
/// to mean the same thing.
struct Pattern: Sendable {
    struct Match {
        let range: Range<String.Index>
        /// The capture groups, in order. A group that did not take part is nil.
        let groups: [String?]
    }

    private let expression: NSRegularExpression

    init(_ pattern: String) {
        // The patterns are literals in this file. A pattern that does not compile is a mistake in this code,
        // so it is force-tried. A run cannot recover from it.
        expression = try! NSRegularExpression(pattern: pattern)
    }

    func matches(_ text: String) -> [Match] {
        let whole = NSRange(text.startIndex..., in: text)

        return expression.matches(in: text, range: whole).compactMap { found in
            guard let range = Range(found.range, in: text) else { return nil }

            let groups = (1..<found.numberOfRanges).map { i -> String? in
                guard let group = Range(found.range(at: i), in: text) else { return nil }
                return String(text[group])
            }

            return Match(range: range, groups: groups)
        }
    }

    /// The first capture group of the first match.
    func firstMatch(_ text: String) -> String? {
        matches(text).first?.groups.first ?? nil
    }

    func replacing(_ text: String, with replacement: String) -> String {
        let whole = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: whole, withTemplate: replacement)
    }
}
