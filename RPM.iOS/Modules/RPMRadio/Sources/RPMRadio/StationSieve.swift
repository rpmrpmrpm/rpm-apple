import Foundation

/// The filters the listener has set on the dial: a format, a genre and an advertising choice. The
/// filters are one value, so "no filter" is stated directly. It is not left as two fields that nobody
/// set.
///
/// This matches the desktop app's `StationSieve`.
///
/// **It filters what is listed.** The directory answers a search with a page of stations, and the sieve
/// narrows that page. This is also why the same filters work on saved presets with no network, and why
/// the count under the heading is correct.
///
/// **The genre is also sent to the directory by the caller.** The sieve cannot ask the directory, because
/// it only reads stations. The opening page shows the most-played stations. It holds almost no stations
/// of a small genre, so filtering that page alone gives an empty list. Use ``RadioGenres/term(_:)`` to get
/// the tag to request. The sieve still runs over the answer, and it removes what the tag brought in. For
/// example, a search for the tag "reggae" also finds reggaeton stations, and the genre check removes them.
///
/// **A station that gives no codec or tags is not kept by a filter that asks about them.** The sieve makes
/// no claims about what a station did not state.
public struct StationSieve: Equatable, Sendable {
    /// The codec wanted, spelled as in ``formats``, or nil for any.
    public var format: String?

    /// The genre wanted, one of ``RadioGenres/all``, or nil for any.
    public var genre: String?

    /// Whether a station's advertising decides if it is kept. ``AdsWanted/either`` keeps both.
    public var ads: AdsWanted

    public init(format: String? = nil, genre: String? = nil, ads: AdsWanted = .either) {
        self.format = format
        self.genre = genre
        self.ads = ads
    }

    /// No filter: every station is kept. This is what the page opens on.
    public static let off = StationSieve()

    /// Whether this sieve filters anything at all.
    public var isOn: Bool { format != nil || genre != nil || ads != .either }

    /// Whether this station is one of the ones asked for. Each filter applies only when it is set. A
    /// sieve with a format and nothing else says nothing about the genre.
    public func keeps(_ station: RadioStation) -> Bool {
        if let format, !isFormat(station.codec, format) { return false }
        // The admin's tags where they set some; the ads rule below keeps the directory's own.
        if let genre, !RadioGenres.is(RadioNames.genres(station.shownTags), genre) { return false }
        switch ads {
        case .either: return true
        case .with: return RadioAds.carriesAds(tags: station.tags, name: station.name, homepage: station.homepage)
        case .without: return !RadioAds.carriesAds(tags: station.tags, name: station.name, homepage: station.homepage)
        }
    }

    /// The stations this sieve keeps, in their original order. When no filter is set, this returns the
    /// list itself, without a copy.
    public func through(_ stations: [RadioStation]) -> [RadioStation] {
        isOn ? stations.filter(keeps) : stations
    }

    /// The formats a station can be filtered by, in the order the menu offers them.
    ///
    /// This is a fixed list, not the codecs on the current page. A menu whose entries change with each
    /// search is hard to learn.
    ///
    /// These four are the codecs that internet streams are served in. FLAC and DAB+ are left out. An
    /// internet directory does not file DAB broadcasts, and only a few stations stream lossless audio, so
    /// those entries would be empty on almost every search.
    public static let formats = ["MP3", "AAC", "AAC+", "OGG"]

    /// The kinds of station that can be filtered by. These are station genres such as talk, news and
    /// sport, not music shelves.
    public static var genres: [String] { RadioGenres.all }

    /// Whether a station's codec is the one asked for.
    ///
    /// A station's codec field is one string, and it can hold several codecs. For example, "AAC+,H.264" is
    /// a video stream, and "MP3, OGG" is a station that serves both. So the field is split on its
    /// separators, and each part is compared on its own. The comparison is exact. "AAC" and "AAC+" are
    /// separate menu entries.
    private func isFormat(_ codec: String?, _ wanted: String) -> Bool {
        guard let codec, !codec.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        return codec
            .split(whereSeparator: { ",/; ".contains($0) })
            .contains { Self.fold(String($0)) == wanted }
    }

    /// Maps a codec spelling to the spelling the menu uses. Directories store the same codec under
    /// different names. For example, "AACP" means AAC+, and "VORBIS" means OGG.
    private static func fold(_ codec: String) -> String {
        switch codec.trimmingCharacters(in: .whitespaces).uppercased() {
        case "AACP", "AAC PLUS", "HE-AAC", "HEAAC": return "AAC+"
        case "VORBIS", "OGG VORBIS": return "OGG"
        case "MPEG", "MPEG3": return "MP3"
        case let other: return other
        }
    }
}

/// Whether advertising is a filter. This is the same choice as the desktop app's `StationSieve.Ads`.
public enum AdsWanted: String, CaseIterable, Sendable {
    case either
    case without
    case with
}
