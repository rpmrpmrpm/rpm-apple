import Foundation

/// Pulls an artist and a track out of what a station announces.
///
/// Ported from `RPM.Core/Radio/IcyTitle.cs`.
///
/// ICY carries one string. The usual convention is `Artist - Title`, but it is never
/// specified. Many stations put a hyphen inside the artist or the title
/// ("Emerson, Lake - Palmer", "Blue Öyster Cult - (Don't Fear) The Reaper - Live"). So the
/// split uses the FIRST separator **with spaces around it**, not any hyphen. `Jay-Z` must
/// stay whole.
///
/// A string that does not look like a pair is left alone. A station that announces its own
/// name, or a bare track title, gives a title with no artist.
public enum IcyTitle {
    /// The separators stations actually use.
    private static let separators = [" - ", " \u{2013} ", " \u{2014} ", " -- "]

    /// Splits one ICY string. The artist is nil when the station does not announce one.
    public static func split(_ announced: String?) -> (artist: String?, title: String?) {
        let raw = announced?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return (nil, nil) }

        let text = spelledOut(raw)

        var at: String.Index?
        var width = 0

        for separator in separators {
            guard let found = text.range(of: separator), found.lowerBound != text.startIndex
            else { continue }

            // The earliest separator wins, so "A - B - C" gives artist "A" and title "B - C". The
            // trailing part is usually a remix or a live tag, so it belongs to the title.
            if at == nil || found.lowerBound < at! {
                at = found.lowerBound
                width = separator.count
            }
        }

        guard let at else { return (nil, text) }

        let artist = String(text[text.startIndex..<at])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(text[text.index(at, offsetBy: width)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // One empty half is not a pair. An announcement such as "- Live from Paris" is a title.
        guard !artist.isEmpty, !title.isEmpty else { return (nil, text) }

        return (artist, title)
    }

    /// Turns an announcement that carries the station's own bookkeeping back into the
    /// usual convention.
    ///
    /// **Not every station announces a sentence.** Many stations on American automation
    /// systems put a list of `key="value"` pairs where the title goes:
    ///
    ///     Zara Larsson - text="Lush Life" song_spot="M" MediaBaseId="0" TAID="0" ...
    ///
    /// Read with the usual convention, this gives an artist "Zara Larsson" and a track
    /// `text="Lush Life" song_spot="M" MediaBaseId="0"...`, which is what would appear on
    /// screen. The part meant for a person is in the pairs, so it is taken out and the rest
    /// is dropped: `text`, or `title` where the station uses that, and `artist` when the
    /// pairs carry one.
    ///
    /// The desktop app also reads `song_spot` in `RPM.Core/Radio/IcyFields.cs`, to tell a
    /// station's idents and ads from its songs. This code does not.
    private static func spelledOut(_ text: String) -> String {
        // A word followed by `="`, at the start or after a space. A title with a quotation
        // mark in it does not match this.
        guard let starts = text.range(of: #"(^|\s)[A-Za-z_][A-Za-z0-9_]*="#,
                                      options: .regularExpression)
        else { return text }

        var said: [String: String] = [:]

        for line in text[starts.lowerBound...].matches(of: pairs()) {
            said[String(line.output.1).lowercased()] = String(line.output.2)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // The text before the pairs start. It is usually the artist.
        let spoken = text[text.startIndex..<starts.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-\u{2013}\u{2014}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let title = [said["title"], said["text"]].compactMap { $0 }.first { !$0.isEmpty }
        let artist = said["artist"].flatMap { $0.isEmpty ? nil : $0 } ?? spoken

        guard let title else { return spoken.isEmpty ? text : spoken }
        guard !artist.isEmpty else { return title }

        return "\(artist) - \(title)"
    }

    /// Built where it is used, not stored. A `Regex` is not `Sendable`, so it cannot be a
    /// shared constant.
    private static func pairs() -> Regex<(Substring, Substring, Substring)> {
        /([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"/
    }

    /// The whole announcement as one line, which is what a strip with one row of text
    /// shows. Empty when the station announced nothing.
    public static func line(_ announced: String?) -> String {
        let (artist, title) = split(announced)

        guard let title else { return "" }
        guard let artist else { return title }
        return "\(artist) \u{b7} \(title)"
    }
}
