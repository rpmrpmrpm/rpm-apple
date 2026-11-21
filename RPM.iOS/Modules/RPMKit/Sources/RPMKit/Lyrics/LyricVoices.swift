import Foundation

/// The second voice in a lyric line: the words a sheet puts in round brackets. These are the rules of
/// the desktop's Pegasus lyrics (`AsideGroups`, `IsAside`, `AsideText` and `Verse` in
/// RPM.Desktop/Presentation/Pegasus/PegasusChrome.xaml.cs), as the Android phone ports them
/// (`LyricVoices` in its `core`).
///
/// Sheets write two singers as one line, with the second singer in brackets: "Milan, darling, Milan
/// (fuck, fuck)". Left in the line, two people's words run together and wrap into the next line. So
/// the bracketed words are shown on a smaller row of their own under the line (``split(_:spans:)``),
/// and the brackets themselves are not shown.
///
/// A line bracketed from end to end is a backing vocal on its own (``isAside(_:)``). It has no verse
/// to sit under, so the lyric view shows it under the line before it while it is sung
/// (``LyricScore/Aside``).
///
/// Places in a text are counted in characters, as ``LyricTiming`` counts them.
public enum LyricVoices {
    /// How much smaller the second voice is drawn than the verse, as on the desktop.
    public static let scale = 0.76

    /// Whether `text` is bracketed from end to end, with one bracket pair around the whole line. A
    /// line that only contains brackets is not: "I wish I understood (yeah)" is the verse, with a
    /// shout in it.
    public static func isAside(_ text: String?) -> Bool {
        guard let text else { return false }
        let line = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard line.count > 2, line[0] == "(", line[line.count - 1] == ")" else { return false }
        return line[1...].firstIndex(of: ")") == line.count - 1
    }

    /// Every bracketed group of `text`, as half-open ranges from the opening bracket to after the
    /// closing one, in the order they were written. Only the outermost brackets count: a group inside
    /// a group belongs to it. A group must have words inside it, and the line must have words outside
    /// its groups; otherwise there is no second voice. Every group counts, however short: "(uh)" is a
    /// second voice as much as a sung answer is.
    public static func groups(_ text: String?) -> [Range<Int>] {
        guard let text else { return [] }
        let chars = Array(text)
        guard chars.count > 2, !isAside(text) else { return [] }

        var found: [Range<Int>] = []
        var depth = 0
        var open = -1
        for (at, char) in chars.enumerated() {
            if char == "(" {
                if depth == 0 { open = at }
                depth += 1
            } else if char == ")", depth > 0 {
                depth -= 1
                if depth == 0, open >= 0 {
                    if !chars[(open + 1)..<at].allSatisfy(\.isWhitespace) { found.append(open..<(at + 1)) }
                    open = -1
                }
            }
        }

        let covered = found.reduce(0) { $0 + $1.count }
        return !found.isEmpty && chars.count > covered ? found : []
    }

    /// One row of a line taken apart: its `text`, its words as spans of that text, and for each of
    /// its letters the place of that letter among the letters of the whole line's spans, which is
    /// what ``KaraokeLight/light(_:now:fades:)`` gives a strength for.
    public struct Row: Sendable, Equatable {
        public let text: String
        public let spans: [WordSpan]
        public let letters: [Int]
    }

    /// A line taken apart into its verse and its second voice.
    public struct Split: Sendable, Equatable {
        public let verse: Row
        public let voice: Row
    }

    /// The line `text` taken apart, or nil when it has no second voice (``groups(_:)``). `spans` are
    /// the line's words, as ``LyricTiming/sweep(_:from:until:)`` cuts them, with their times. Each row
    /// keeps the times of the words it takes.
    ///
    /// In the second voice, words of one group are joined by a space and two groups by a comma, so two
    /// answers written apart do not read as one. The brackets are left out. A word cut by a bracket is
    /// shared between the two rows, and what follows the bracket in the verse is joined to the verse
    /// without a space.
    public static func split(_ text: String, spans: [WordSpan]) -> Split? {
        let groups = groups(text)
        guard !groups.isEmpty else { return nil }
        let chars = Array(text)
        func group(at place: Int) -> Int { groups.firstIndex { $0.contains(place) } ?? -1 }

        var verse = RowWriter()
        var voice = RowWriter()
        var letter = 0
        for (k, word) in spans.enumerated() {
            for c in 0..<max(0, word.length) {
                let place = word.start + c
                let inside = group(at: place)
                if place >= 0, place < chars.count {
                    let char = chars[place]
                    if inside < 0 {
                        // The verse after a bracket inside one word ("on (and on).") goes on without a
                        // space.
                        verse.add(k, group: inside, char, from: word, letter: letter, apart: c == 0)
                    } else if char != "(" && char != ")" {
                        voice.add(k, group: inside, char, from: word, letter: letter, apart: true)
                    }
                }
                letter += 1
            }
        }
        return Split(verse: verse.row(), voice: voice.row())
    }

    /// A backing line (``isAside(_:)``) as its row shows it: `text` without its brackets, with `spans`,
    /// its words as ``LyricTiming/sweep(_:from:until:)`` cuts them, made to fit.
    public static func unbracketed(_ text: String, spans: [WordSpan]) -> Row {
        let chars = Array(text)
        var row = RowWriter()
        var letter = 0
        for (k, word) in spans.enumerated() {
            for c in 0..<max(0, word.length) {
                let place = word.start + c
                if place >= 0, place < chars.count, chars[place] != "(", chars[place] != ")" {
                    let apart = c == 0 || row.isEmpty
                    row.add(k, group: -1, chars[place], from: word, letter: letter, apart: apart)
                }
                letter += 1
            }
        }
        return row.row()
    }
}

/// Writes one row of ``LyricVoices`` a letter at a time.
private struct RowWriter {
    private var text: [Character] = []
    private var spans: [WordSpan] = []
    private var letters: [Int] = []
    private var word = -1
    private var group = -1

    var isEmpty: Bool { text.isEmpty }

    /// Adds `char`, letter `letter` of the whole line, from word `k` (`from`) in group `group` (-1 for
    /// the verse). A new word is set apart by a space where `apart` says so, or by a comma where it
    /// starts another group.
    mutating func add(_ k: Int, group: Int, _ char: Character, from: WordSpan, letter: Int, apart: Bool) {
        if k != word || spans.isEmpty {
            if !text.isEmpty && apart {
                let between = group >= 0 && self.group >= 0 && group != self.group ? ", " : " "
                text.append(contentsOf: between)
            }
            spans.append(WordSpan(start: text.count, length: 0, from: from.from, to: from.to))
            word = k
            self.group = group
        }
        text.append(char)
        let last = spans[spans.count - 1]
        spans[spans.count - 1] = WordSpan(start: last.start, length: last.length + 1,
                                          from: last.from, to: last.to)
        letters.append(letter)
    }

    func row() -> LyricVoices.Row {
        LyricVoices.Row(text: String(text), spans: spans, letters: letters)
    }
}
