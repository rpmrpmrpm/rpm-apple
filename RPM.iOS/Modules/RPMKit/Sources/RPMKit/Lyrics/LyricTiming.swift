import Foundation

/// One word of a line: where it sits in the text, in characters, and the stretch of the record it is
/// sung over, in seconds from the track's start.
public struct WordSpan: Equatable, Sendable {
    public let start: Int
    public let length: Int
    public let from: Double
    public let to: Double

    public init(start: Int, length: Int, from: Double, to: Double) {
        self.start = start; self.length = length; self.from = from; self.to = to
    }
}

/// Which word of a line is being sung, for karaoke: the desktop's `LyricTiming.Sweep` (RPM.Core/Lyrics),
/// the shared-out half, as the Android TV ports it. LRCLIB's sheets carry no word stamps, so the line is
/// spread across its words by their length, from the line's own moment to the next line's, and no slower
/// than ``slowestChars`` characters a second: past that the sweep finishes and the line stays lit, rather
/// than crawling through an instrumental.
public enum LyricTiming {
    public static let slowestChars = 7.0

    public static func sweep(_ text: String?, from: Double, until: Double) -> [WordSpan] {
        let words = split(text)
        guard !words.isEmpty else { return [] }
        let chars = words.reduce(0) { $0 + $1.length }
        let capped = from + Double(chars) / slowestChars
        let end = until.isFinite ? min(max(from, until), capped) : capped
        let run = max(0, end - from)
        var soFar = 0
        return words.map { word in
            // Measured from the start of the line, so rounding cannot drift the last word off the end.
            let opens = from + run * Double(soFar) / Double(max(1, chars))
            soFar += word.length
            let closes = from + run * Double(soFar) / Double(max(1, chars))
            return WordSpan(start: word.start, length: word.length, from: opens, to: closes)
        }
    }

    /// Runs of anything that is not whitespace, by character offset; punctuation stays with its word.
    private static func split(_ text: String?) -> [(start: Int, length: Int)] {
        guard let text, !text.allSatisfy(\.isWhitespace) else { return [] }
        var words: [(start: Int, length: Int)] = []
        var start: Int?
        for (at, character) in text.enumerated() {
            if character.isWhitespace {
                if let open = start { words.append((open, at - open)); start = nil }
            } else if start == nil {
                start = at
            }
        }
        if let open = start { words.append((open, text.count - open)) }
        return words
    }
}

/// One word's stretch of the record, in seconds from the track's start.
public struct MeasuredWord: Codable, Equatable, Sendable {
    public let from: Double
    public let to: Double

    public init(from: Double, to: Double) { self.from = from; self.to = to }
}

/// One lyric line as a desktop or the transcoder measured it: its place in the sheet, its moment and
/// text there, its words in reading order. Mirrors the API's `lyric-timing` lines.
public struct MeasuredLine: Codable, Equatable, Sendable {
    public let index: Int
    public let seconds: Double
    public let text: String
    public let words: [MeasuredWord]

    public init(index: Int, seconds: Double, text: String, words: [MeasuredWord]) {
        self.index = index; self.seconds = seconds; self.text = text; self.words = words
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        words = try c.decodeIfPresent([MeasuredWord].self, forKey: .words) ?? []
    }

    private enum CodingKeys: String, CodingKey { case index, seconds, text, words }
}

/// One line of this device's sheet, sent to have the record timed against it.
public struct SheetLine: Encodable, Equatable, Sendable {
    public let index: Int
    public let seconds: Double
    public let text: String

    public init(index: Int, seconds: Double, text: String) {
        self.index = index; self.seconds = seconds; self.text = text
    }
}

/// How measured word timing is matched to this device's sheet, as the Android TV does it. A line
/// is used only where it is the same line on this device's sheet: the same text and the same
/// moment, and as many words; every other line keeps the shared-out guess
/// (``LyricTiming/sweep(_:from:until:)``).
public enum MeasuredLyrics {
    /// How far apart two moments may be and still be the same line's: LRC stamps are kept to the
    /// hundredth.
    static let sameMoment = 0.05

    /// The measured words of the line `text` at `seconds`, as spans of `text`, or nil where nothing
    /// measured matches it.
    public static func forLine(_ measured: [MeasuredLine], text: String, seconds: Double) -> [WordSpan]? {
        guard let line = measured.first(where: { $0.text == text && abs($0.seconds - seconds) < sameMoment })
        else { return nil }
        let shape = LyricTiming.sweep(text, from: seconds, until: .infinity)
        guard shape.count == line.words.count else { return nil }
        return zip(shape, line.words).map { span, word in
            WordSpan(start: span.start, length: span.length, from: word.from, to: max(word.from, word.to))
        }
    }

    /// Whether `measured` covers most of `sheet`'s sung lines (three in four): a sheet this well
    /// covered needs no measurement asked for.
    public static func covers(_ measured: [MeasuredLine], sheet: LyricSheet) -> Bool {
        let sung = sheet.lines.filter { !LyricSheet.isWordless($0.text) }
        guard !sung.isEmpty else { return true }
        let placed = sung.filter { forLine(measured, text: $0.text, seconds: $0.seconds) != nil }.count
        return placed * 4 >= sung.count * 3
    }
}
