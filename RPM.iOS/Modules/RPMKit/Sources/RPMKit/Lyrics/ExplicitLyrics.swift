import Foundation

/// Picks the uncensored sheet for an explicit record from the sheets LRCLIB offers.
///
/// LRCLIB often holds two sheets for one song: the explicit one and the clean (edited) one. They have
/// the same names and nearly the same length, so the exact lookup can return either. For a record marked
/// explicit, the explicit sheet is the right one. This gives each candidate a score and keeps the best.
///
/// **The score.** Each masked word (a word with `*` in it, a `#` after a letter or another `#`, or a
/// `[censored]` marker) costs ``maskPenalty`` points. Each word from ``words`` adds one point. A clean
/// sheet with masks scores below zero, and the explicit sheet scores above it. A clean sheet that drops
/// the words without masking them scores zero, and the explicit sheet still scores more.
///
/// **The same rules on every device.** The desktop (`RPM.Core/Lyrics/ExplicitLyrics.cs`) and the Android
/// apps (core `ExplicitLyrics.kt`) use the same word list, the same split into words and the same score.
/// Change all three together.
public enum ExplicitLyrics {
    /// What one masked word costs. It is large, so that one mask outweighs several explicit words.
    public static let maskPenalty = 10

    /// Common explicit words, in lower case and letters only. They come from the swearing list of the
    /// desktop's `LyricCensor`, without the words that also have an innocent meaning (such as "hell" or
    /// "cock"). A word is counted when the letters of a word in the sheet are exactly one of these.
    public static let words: Set<String> = [
        "arse", "arsehole", "ass", "asshole", "assholes",
        "bastard", "bastards", "bitch", "bitches", "bitchin", "bitching", "bollocks", "bullshit",
        "cunt", "cunts", "damn", "dammit",
        "fuck", "fucked", "fucker", "fuckers", "fuckin", "fucking", "fucks", "goddamn",
        "motherfucker", "motherfuckers", "motherfuckin", "motherfucking",
        "piss", "pissed", "pussies", "pussy",
        "shit", "shits", "shittin", "shitting", "shitty", "slut", "sluts",
        "tits", "titties", "twat", "wanker", "whore", "whores",
    ]

    /// The sheet's score: one point for each explicit word, minus ``maskPenalty`` for each masked word.
    public static func score(_ sheet: LyricSheet) -> Int {
        var score = 0
        for line in sheet.lines {
            for raw in line.text.split(whereSeparator: { $0.isWhitespace }) {
                let token = raw.lowercased()
                if isMasked(token) {
                    score -= maskPenalty
                } else if words.contains(token.filter { $0.isLetter }) {
                    score += 1
                }
            }
        }
        return score
    }

    /// The best sheet for an explicit record, or `.empty` when there is no candidate. The highest
    /// ``score(_:)`` wins. On a tie, `exact` wins if it is one of the best. Otherwise the first of the best
    /// in `found` wins, so LRCLIB's own order decides.
    ///
    /// - Parameter exact: The exact lookup's answer, or `.empty` when it had none.
    /// - Parameter found: The search's candidates, in LRCLIB's order. Sheets without timings are ignored.
    public static func pick(exact: LyricSheet, found: [LyricSheet]) -> LyricSheet {
        var best = LyricSheet.empty
        var bestScore = Int.min

        // The exact answer is looked at first, and a later candidate replaces it only with a higher
        // score. That is what makes a tie keep the exact answer.
        if exact.isSynced {
            best = exact
            bestScore = score(exact)
        }

        for sheet in found where sheet.isSynced {
            let candidate = score(sheet)
            if candidate > bestScore {
                best = sheet
                bestScore = candidate
            }
        }

        return best
    }

    /// Whether a word (already in lower case) is masked: it has a `*`, a `#` after a letter or after
    /// another `#` ("f#ck", "###"), or it is a "[censored]" or "(censored)" marker. A `#` at the start of
    /// a word, as in "#1", is not a mask.
    private static func isMasked(_ token: String) -> Bool {
        if token.contains("*") || token.contains("[censored") || token.contains("(censored") {
            return true
        }

        let characters = Array(token)
        for (previous, current) in zip(characters, characters.dropFirst())
        where current == "#" && (previous.isLetter || previous == "#") {
            return true
        }
        return false
    }
}
