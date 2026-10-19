import Foundation
import RPMKit

/// One artist tag, read as the list of acts it names.
///
/// Ported from `RPM.Core/Metadata/Providers/ArtistCredit.cs`. Both heads ask the same
/// question of the same field and have to get the same answer, so the separators and the
/// limits are the desktop's, character for character.
public enum ArtistCredit {
    /// The names in one artist credit: the separators a tagger actually types, and
    /// nothing cleverer.
    ///
    /// A comma, a slash, an ampersand, a semicolon, or the word "feat" in any of its
    /// spellings. Every one of them also appears inside artist names ("Earth, Wind &
    /// Fire", "AC/DC"), so this is only asked about a credit something else has already
    /// failed to recognise as one act. Splitting is the second guess, never the first.
    public static func split(_ credit: String?) -> [String] { cut(credit, on: separators) }

    /// The same, with the joining words counted as separators too: "with", "and", and
    /// the bare "x" that some collaborations are written with.
    ///
    /// Not the ordinary reading, and it must not become it. Every one of these words
    /// lives inside real names ("Sleeping With Sirens", "Bob and Earl"), and a credit is
    /// far more often one act with a long name than two acts joined by a word. This is
    /// the question asked second, by a caller that already has reason to believe the
    /// credit names more than one act and can check the answer against acts it knows.
    /// See ``ArtistWall/build(_:)``, the one caller that decides anything on it.
    public static func splitWide(_ credit: String?) -> [String] { cut(credit, on: wideSeparators) }

    /// The lead name in a credit that turns out to name more than one act, or nil where
    /// there is no second name to be had. A single-name credit gives back nil rather
    /// than itself, so a caller cannot ask the same question twice.
    public static func first(_ credit: String?) -> String? {
        let names = split(credit)
        guard names.count > 1, !NameMatch.same(names[0], credit) else { return nil }
        return names[0]
    }

    /// Whether a name is the compilation marker rather than somebody. All three
    /// spellings taggers write, compared the way every other name is.
    public static func isVariousArtists(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        return variousNames.contains(NameMatch.squash(name))
    }

    /// Where a credit stops being a credit. Eight is already a long row, and a field
    /// naming more acts than that is a compilation's track list in the artist tag.
    public static let maxCredited = 8

    /// The app's own spelling of the compilation marker, matching
    /// `AlbumResolver.VariousArtists` on the desktop.
    public static let variousArtists = "Various Artists"

    /// The same names as `split`, grouped by the guest markers rather than run together:
    /// "Tyler, The Creator feat. Frank Ocean" is `[["Tyler", "The Creator"], ["Frank Ocean"]]`
    /// (the desktop's `SplitGuests`).
    ///
    /// For a caller that puts split names back together (`ArtistWall`'s rejoin). "feat" says
    /// outright that what follows is somebody else; a comma does not, and half the names it
    /// sits inside are one act. The cap and the dropped duplicates are counted across the
    /// whole credit, not per group.
    public static func splitGuests(_ credit: String?) -> [[String]] {
        guard let credit, !credit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var groups: [[String]] = []
        var all: [String] = []
        for group in parts(of: credit, on: guestSeparators) {
            var names: [String] = []
            for part in parts(of: group, on: nameSeparators) {
                guard let name = named(part, already: all) else { continue }
                all.append(name)
                names.append(name)
                if all.count == maxCredited { break }
            }
            if !names.isEmpty { groups.append(names) }
            if all.count == maxCredited { break }
        }
        return groups
    }

    // ── the cut ──

    private static func cut(_ credit: String?, on separators: NSRegularExpression) -> [String] {
        guard let credit, !credit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var names: [String] = []
        for part in parts(of: credit, on: separators) {
            guard let name = named(part, already: names) else { continue }
            names.append(name)
            if names.count == maxCredited { break }
        }

        return names
    }

    /// One cut piece as a name, or nil where it is not one. A single character is not a
    /// name, it is what is left of one when a splitter cut in the wrong place. Duplicates go
    /// too: "A feat. A" is one artist typed twice. And the compilation marker is not a person.
    private static func named(_ part: String, already: [String]) -> String? {
        let name = part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()[]-\u{2013}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard name.count >= 2,
              !isVariousArtists(name),
              !already.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame })
        else { return nil }
        return name
    }

    /// What `Regex.Split` does in C#: the stretches of the string between matches, in
    /// order, including the empty ones at either end.
    private static func parts(of text: String, on separators: NSRegularExpression) -> [String] {
        let whole = NSRange(text.startIndex..., in: text)
        var pieces: [String] = []
        var cut = text.startIndex

        for match in separators.matches(in: text, range: whole) {
            guard let found = Range(match.range, in: text) else { continue }
            pieces.append(String(text[cut..<found.lowerBound]))
            cut = found.upperBound
        }

        pieces.append(String(text[cut...]))
        return pieces
    }

    private static let variousNames: Set<String> = [
        NameMatch.squash("Various"),
        NameMatch.squash("Various Artist"),
        NameMatch.squash(variousArtists),
    ]

    /// The separators. A comma, a slash, an ampersand, and a semicolon, which is what
    /// most taggers put in place of the null a 2.4 tag really separates a list with.
    ///
    /// "feat" and its spellings need a bracket or a space in front of them, never
    /// nothing: without that the pattern cuts "Defeat Ed" in half at the "feat".
    private static let separators = try! NSRegularExpression(
        pattern: #"\s*[,;/&]\s*|[\s(\[]+(?:feat\.?|featuring|ft\.?)\s+"#,
        options: [.caseInsensitive])

    /// The two halves of `separators`, for `splitGuests`: the guest markers alone, and the
    /// punctuation alone. Their union is the pattern above, so the grouped reading and the
    /// flat one are the same names.
    private static let guestSeparators = try! NSRegularExpression(
        pattern: #"[\s(\[]+(?:feat\.?|featuring|ft\.?)\s+"#,
        options: [.caseInsensitive])

    private static let nameSeparators = try! NSRegularExpression(pattern: #"\s*[,;/&]\s*"#)

    /// The separators above, and the words a collaboration is joined with. Whole words
    /// with space either side, which is what keeps "x" out of "Malcolm X" and "and" out
    /// of "Land".
    private static let wideSeparators = try! NSRegularExpression(
        pattern: #"\s*[,;/&]\s*|[\s(\[]+(?:feat\.?|featuring|ft\.?)\s+|\s+(?:with|and|x)\s+"#,
        options: [.caseInsensitive])
}
