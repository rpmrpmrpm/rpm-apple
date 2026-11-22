import Foundation

/// A record's name with the bracketed editions taken off the end (the desktop's `AlbumTitle`).
/// "Short N' Sweet (Deluxe)" is a record called Short N' Sweet, in its Deluxe edition. The record
/// page shows the two parts on separate lines.
///
/// - **Only from the end.** A bracketed group in the middle or at the start is part of the name:
///   "(What's the Story) Morning Glory?" keeps it. Groups are removed from the end again and again,
///   so "... (Deluxe) [Remastered]" loses both.
/// - **Only when the brackets hold an edition** (``isAside(_:)``). "The Guide (Wommat)" is really
///   called that, so it stays.
/// - A title that is only brackets, such as "( )", keeps them, so the heading is never empty.
public struct AlbumTitle: Equatable, Sendable {
    /// The title exactly as it was tagged. Use it wherever the record is named.
    public let full: String
    /// The title without the trailing editions.
    public let name: String
    /// What was inside those brackets, in reading order, without the brackets. Empty for most
    /// records.
    public let editions: [String]

    public static func split(_ title: String?) -> AlbumTitle {
        let full = title ?? ""
        var name = trimmedEnd(full)
        var editions: [String] = []
        while let peeled = peel(name) {
            let (before, inside) = peeled
            if before.isEmpty { break }
            editions.insert(inside, at: 0)
            name = before
        }
        return AlbumTitle(full: full, name: name, editions: editions)
    }

    /// Whether the text between a pair of brackets is a note about which recording or pressing
    /// this is, and not part of the name (the desktop's `TitleAsides.IsAside`). The test is a list
    /// of words, not the shape: a phrase this does not know is read as part of the name, which is
    /// the safe way to be wrong. A credit ("feat. …", "with …") is never an aside.
    public static func isAside(_ inside: String) -> Bool {
        let phrase = inside.trimmingCharacters(in: .whitespacesAndNewlines)
        if phrase.isEmpty || isCredit(phrase) { return false }
        return words(phrase).contains { qualifiers.contains($0) }
    }

    /// One trailing bracketed group: what is left of the title, and what was inside. Nil when the
    /// title does not end in one, or the group is not an edition. The closing bracket is counted
    /// back to its own opener, so "(Deluxe (2019))" comes off whole.
    private static func peel(_ title: String) -> (String, String)? {
        guard let last = title.last else { return nil }
        let open: Character, close: Character
        switch last {
        case ")": (open, close) = ("(", ")")
        case "]": (open, close) = ("[", "]")
        default: return nil
        }
        var depth = 0
        var i = title.endIndex
        while i > title.startIndex {
            i = title.index(before: i)
            let c = title[i]
            if c == close {
                depth += 1
            } else if c == open {
                depth -= 1
                if depth == 0 {
                    let inner = title[title.index(after: i)..<title.index(before: title.endIndex)]
                    let inside = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isAside(inside) else { return nil }
                    return (trimmedEnd(String(title[..<i])), inside)
                }
            }
        }
        // A bracket that is never closed, such as "Album (Deluxe", is part of the title.
        return nil
    }

    private static func trimmedEnd(_ text: String) -> String {
        var s = Substring(text)
        while let last = s.last, last.isWhitespace { s = s.dropLast() }
        return String(s)
    }

    /// The phrase's words, lower case, split on every character that is not a letter or a digit.
    private static func words(_ phrase: String) -> [String] {
        phrase.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    /// Whether the phrase opens with a credit mark that ends where its next word begins.
    private static func isCredit(_ phrase: String) -> Bool {
        let lower = phrase.lowercased()
        for mark in creditMarks where lower.hasPrefix(mark) {
            guard let end = mark.last, end.isLetter else { return true }
            let rest = lower.dropFirst(mark.count)
            guard let after = rest.first else { return true }
            if after == "." || after == ":" || after.isWhitespace { return true }
        }
        return false
    }

    private static let creditMarks = ["feat.", "feat", "featuring", "ft.", "ft", "with", "w/"]

    /// The words a version or a pressing is described with (the desktop's
    /// `TitleAsides.Qualifiers`). English only.
    private static let qualifiers: Set<String> = [
        // what was done to the recording
        "mix", "mixes", "mixed", "remix", "remixes", "remixed", "edit", "edits", "edited",
        "version", "versions", "remaster", "remastered", "remasters", "rerecorded", "rerecording",
        "dub", "instrumental", "acoustic", "unplugged", "acappella", "cappella", "karaoke", "reprise",
        // where and how it was taken down
        "live", "demo", "rehearsal", "session", "sessions", "take", "outtake", "bootleg", "concert",
        // which cut of it this is
        "radio", "single", "album", "extended", "original", "alternate", "clean", "explicit",
        "censored", "mono", "stereo", "club", "dance", "vocal",
        // which pressing carries it
        "deluxe", "edition", "expanded", "anniversary", "reissue", "bonus", "unreleased",
    ]
}
