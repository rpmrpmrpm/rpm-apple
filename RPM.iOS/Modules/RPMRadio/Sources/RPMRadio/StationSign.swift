import Foundation

/// The three- or four-letter mark a station is known by on the dial card: its call sign.
///
/// This matches the desktop app's `StationSign`. The dial card has little room, so it shows a short mark
/// rather than a full name. For example, "Smooth Jazz Lounge Radio, The Netherlands" shows as SJL. That is
/// short enough to fit, and it still tells one station from its neighbour. The directory does not publish
/// call signs, so the mark is made from the name the way a listener would say it aloud: the letters people
/// actually keep.
///
/// The function is pure, so the mark on the card and the mark beside the row always match. The mark is
/// not saved with a preset.
public enum StationSign {
    /// The longest mark. The dial card is laid out for four letters. Longer marks do not line up in a
    /// column.
    private static let mostLetters = 4

    /// Words that say "this is a radio station", and so say nothing about WHICH one. They are dropped while
    /// anything else is left. "Radio Nova" gives NOVA. "Radio" on its own is kept, and gives RADI.
    private static let noise: Set<String> = [
        "RADIO", "RADIOS", "RADIU", "RADION", "FM", "AM", "HD", "DAB", "STATION", "STATIONS",
        "ONLINE", "LIVE", "STREAM", "STREAMING", "NET", "WEB", "DIGITAL", "CHANNEL", "THE",
    ]

    /// Small joining words, such as OF and DE. They are left out when the mark is built, so "Voice of the
    /// Nation" gives VON and not VOTN. They are kept when removing them would leave no words.
    private static let joiners: Set<String> = [
        "OF", "AND", "THE", "A", "AN", "DE", "DA", "DI", "DU", "DEL", "LA", "LE", "LES", "EL",
        "IL", "DER", "DIE", "DAS", "VAN", "VON", "EN", "ET", "Y",
    ]

    /// The station's mark. The mark is never empty for a name with a letter or a digit in it, and it is
    /// never longer than four characters.
    public static func of(_ name: String?) -> String {
        let words = self.words(name)
        guard !words.isEmpty else { return "" }

        // A name made only of joining words still needs a mark.
        var carriers = words.filter { !joiners.contains($0) }
        if carriers.isEmpty { carriers = words }

        // When the name is one short word, that word is the mark. It is the call sign listeners already
        // use: NPO, BBC, KEXP, 538. Initials would throw it away. A number after it stays with it, so
        // "BBC Radio 1" gives BBC1, which tells it apart from its sister stations. This applies only with at
        // most two words. With a third word, a short first word is a prefix, not the sign.
        let lead = carriers[0]
        if carriers.count <= 2, (2...mostLetters).contains(lead.count) {
            let number = carriers.dropFirst().first(where: isNumber)
            let joined = number.map { lead + $0 } ?? lead

            if (3...mostLetters).contains(joined.count) { return joined }
            if lead.count >= 3 { return lead }
        }

        // Three or more words: use their initials, in order. For example, "Smooth Jazz Lounge" gives SJL.
        if carriers.count > 2 {
            return String(carriers.prefix(mostLetters).compactMap(\.first))
        }

        // Otherwise, use the opening letters of the words, run together, up to four. Listeners know a
        // station by these letters. "CLASSICAL MUSIC" gives CLAS, and "Q-MUSIC" gives QMUS.
        var run = ""
        for word in carriers {
            run += word
            if run.count >= mostLetters { break }
        }
        return String(run.prefix(mostLetters))
    }

    /// The name split into words for signing. The words are in upper case, with accents and punctuation
    /// removed. The "radio" words are dropped, unless they are all there is.
    private static func words(_ name: String?) -> [String] {
        let text = fold(name ?? "")

        var words: [String] = []
        var word = ""

        for c in text {
            // Letters and digits build words. Any other character ends a word, for example a dash, a dot or
            // a symbol. A run of digits is its own word, so "Radio 538" gives 538 and not R5.
            if c.isLetter || c.isNumber {
                if let last = word.last, last.isNumber != c.isNumber {
                    words.append(word)
                    word = ""
                }
                word.append(c)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }

        let carried = words.filter { !noise.contains($0) }
        return carried.isEmpty ? words : carried
    }

    /// Upper case with accents removed. "Rádio Comercial" and "Radio Comercial" give the same mark. No
    /// mark carries an accent, because the dial's letter spacing is not set up for accents.
    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isNumber(_ word: String) -> Bool {
        word.first?.isNumber == true
    }
}
