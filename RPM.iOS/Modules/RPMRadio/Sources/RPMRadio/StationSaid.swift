import Foundation

/// What a station's announcement says, made printable: an ad break, or a song with its title and
/// perhaps its artist. The Android app's `Icy.said` gives the same answers.
///
/// The player, the mini player and the lock screen read the song from here, and ``SongCovers``
/// asks for the song's cover with ``coverAsk``.
public enum StationSaid: Hashable, Sendable {
    case adBreak
    case song(artist: String?, title: String)

    /// The announcement as it reads under the station's name, or nil when there is nothing to print:
    /// blank, the end of an ad break, or only the station's own name.
    public static func of(_ announced: String?, station: String) -> StationSaid? {
        let text = announced?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, !RadioAds.isBreakOver(text) else { return nil }
        if RadioAds.isAdBreak(text) { return .adBreak }

        let spoken = withoutStation(text, station: station)
        let name = station.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, spoken.caseInsensitiveCompare(name) != .orderedSame else { return nil }

        let (artist, title) = IcyTitle.split(spoken)
        guard let title, !title.isEmpty else { return nil }
        return .song(artist: artist, title: title)
    }

    /// The song's title, or nil for an ad break.
    public var title: String? {
        if case .song(_, let title) = self { return title }
        return nil
    }

    /// The song's artist, or nil for an ad break and for a song announced without one.
    public var artist: String? {
        if case .song(let artist, _) = self { return artist }
        return nil
    }

    /// The artist and title to ask the song's cover for. Nil unless both are there and each is at
    /// least two letters long: an announcement such as "-" or "X" is not a song worth asking about.
    public var coverAsk: SongAsk? {
        guard case .song(let artist?, let title) = self else { return nil }
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.count >= 2, t.count >= 2 else { return nil }
        return SongAsk(artist: a, title: t)
    }

    /// The separators that may follow a station's name at the start of an announcement.
    private static let separators = [" - ", " \u{2013} ", " \u{2014} ", " -- "]

    /// The announcement without a leading station name and separator ("Station Name - Now playing"),
    /// or whole when taking it off would leave nothing.
    static func withoutStation(_ text: String, station: String) -> String {
        let name = station.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let head = text.range(of: name, options: [.caseInsensitive, .anchored])
        else { return text }

        let rest = text[head.upperBound...]
        for separator in separators where rest.hasPrefix(separator) {
            let after = rest.dropFirst(separator.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return after.isEmpty ? text : after
        }
        return text
    }
}

/// An artist and a title to ask a song's cover for (``StationSaid/coverAsk``).
public struct SongAsk: Hashable, Sendable {
    public let artist: String
    public let title: String

    public init(artist: String, title: String) {
        self.artist = artist
        self.title = title
    }

    /// The artist and the title folded (case, accents, spacing), so two spellings of one
    /// announcement share an answer.
    var key: String { Self.fold(artist) + "\u{0}" + Self.fold(title) }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
