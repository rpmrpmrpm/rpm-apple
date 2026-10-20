import Foundation
import RPMKit

/// Which of the app's genres a tag means. This is a port of the desktop's `Genres.Match`,
/// with the same shelves and styles (generated from `scripts/subgenres.json` into
/// `SubgenreTable`), the same aliases and the same order of lookup. So a record is filed
/// under the same genre on every platform.
public enum Genres {
    /// The shelf for a record that fits none of the others. It is left off the genres wall,
    /// which files that music under ``GenreWall/unclassified``.
    public static let unknown = "Other / Unknown"

    /// Every shelf, in the order the wall reads.
    public static var all: [String] { SubgenreTable.shelves }

    /// The shelf this tag means, or nil when it means none of them.
    ///
    /// This is one walk down the tag's keys (see ``GenreText/keys(of:)``). For each key it
    /// asks the styles and then the shelves, and the first answer of either kind wins. A
    /// style carries its own shelf, so "Deep House" is a House record. If the styles were
    /// checked for the whole tag first, and the shelves after, then "Pop Rap" would be filed
    /// under Pop, because the shelf table answers to its first word.
    public static func match(_ tag: String?) -> String? {
        guard let tag, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for key in GenreText.keys(of: tag) {
            if let genre = styleKeys[key] { return genre }
            if let genre = shelfKeys[key] { return genre }
        }
        return nil
    }

    /// Other names that the catalogues use for these genres. This list is copied from the
    /// desktop's `Genres.Aliases`, which is also written by hand. Change both together.
    private static let aliases: [(alias: String, genre: String)] = [
        ("rocknroll", "Rock"), ("rockandroll", "Rock"),
        ("rb", "R&B"), ("rnb", "R&B"), ("randb", "R&B"), ("rhythmandblues", "R&B"),
        ("funksoul", "Funk"), ("motown", "Soul"),
        ("electronica", "Electronic / Dance"), ("edm", "Electronic / Dance"),
        ("hiphoprap", "Hip-Hop / Rap"),
        ("worldmusic", "World"), ("ethnic", "World"),
        ("gospel", "Religious"), ("christian", "Religious"), ("spiritual", "Religious"),
        ("ost", "Soundtrack"), ("filmscore", "Soundtrack"), ("stagescreen", "Soundtrack"),
        ("spoken", "Spoken Word"), ("audiobook", "Spoken Word"),
        ("ska", "Reggae"),
        ("international", "World"), ("score", "Soundtrack"),
        ("game", "Video Game"), ("vgm", "Video Game"),
        ("videogamesoundtrack", "Video Game"), ("gamesoundtrack", "Video Game"),
        ("rbsoul", "R&B"),
        ("worldinternational", "World"),
        ("gospelreligious", "Religious"),
        ("soundtrackscore", "Soundtrack"),
    ]

    /// Every spelling that leads to a shelf. These are the label, each half of a slashed
    /// label (three letters or more, so that "R&B" does not give a key "r"), and the
    /// aliases. The first one wins.
    private static let shelfKeys: [String: String] = {
        var keys: [String: String] = [:]
        for genre in SubgenreTable.shelves where genre != unknown {
            for key in GenreText.keys(of: genre, breaks: GenreText.separators) where key.count >= 3 {
                if keys[key] == nil { keys[key] = genre }
            }
        }
        for (alias, genre) in aliases where keys[alias] == nil {
            keys[alias] = genre
        }
        return keys
    }()

    /// The folded name of every style, and the shelf it hangs off. A name that is shared by
    /// several shelves, or that is spelled like a blocked word, gets no key. The first one wins.
    private static let styleKeys: [String: String] = {
        var keys: [String: String] = [:]
        for style in SubgenreTable.styles {
            let key = GenreText.fold(style.name)
            if key.isEmpty || SubgenreTable.sharedKeys.contains(key)
                || SubgenreTable.blockedKeys.contains(key) { continue }
            if keys[key] == nil { keys[key] = style.genre }
        }
        return keys
    }()
}

extension Genres {
    /// The styles this tag names, each by its name in `SubgenreTable`: "Trip Hop", "Baroque".
    /// A tag may list several ("classical, romantic classical, classical period"), so each
    /// entry is read on its own. Empty when it names none, which is most tags. The desktop's
    /// song radio reads a record's styles the same way.
    public static func styles(_ tag: String?) -> Set<String> {
        guard let tag, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var found: Set<String> = []
        for entry in tag.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }) {
            for key in GenreText.keys(of: String(entry)) {
                if let name = styleNames[key] {
                    found.insert(name)
                    break
                }
            }
        }
        return found
    }

    /// The same keys as the style lookup that `match` uses, to the style's own name instead
    /// of its shelf.
    private static let styleNames: [String: String] = {
        var keys: [String: String] = [:]
        for style in SubgenreTable.styles {
            let key = GenreText.fold(style.name)
            if key.isEmpty || SubgenreTable.sharedKeys.contains(key)
                || SubgenreTable.blockedKeys.contains(key) { continue }
            if keys[key] == nil { keys[key] = style.name }
        }
        return keys
    }()
}

/// How a tag is folded and cut into the keys that a lookup tries. This is the desktop's `GenreText`.
enum GenreText {
    /// The characters that a shelf label is cut on.
    static let separators: Set<Character> = ["/", ",", "&", ";", "|"]

    /// The characters that a tag is cut into words on when it is looked up.
    static let wordBreaks: Set<Character> = ["/", ",", "&", ";", "|", " ", "-", "_"]

    /// Keeps only letters and digits, in lower case. So "Hip-Hop", "hip hop" and "HipHop"
    /// all give one key.
    static func fold(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber }).lowercased()
    }

    /// The whole label, then its parts cut on `breaks`, from left to right.
    static func keys(of value: String, breaks: Set<Character>) -> [String] {
        var keys = [fold(value)]
        if value.contains(where: breaks.contains) {
            keys += value.split(whereSeparator: breaks.contains).map { fold(String($0)) }.filter { !$0.isEmpty }
        }
        return keys
    }

    /// The whole tag, then each phrase (cut on the separators), then each word. The whole
    /// tag comes first, then the phrases, then the words. A key that uses more of the tag
    /// knows more about it. For example, "cloud rap, trap" offers "cloud rap" as a whole
    /// before it is cut into "cloud" and "rap".
    static func keys(of value: String) -> [String] {
        var keys = [fold(value)]
        if value.contains(where: separators.contains) {
            keys += value.split(whereSeparator: separators.contains).map { fold(String($0)) }.filter { !$0.isEmpty }
        }
        if value.contains(where: wordBreaks.contains) {
            keys += value.split(whereSeparator: wordBreaks.contains).map { fold(String($0)) }.filter { !$0.isEmpty }
        }
        return keys
    }
}

/// One card on the genres wall: the genre, and the albums filed under it.
public struct GenreWallItem: Sendable, Equatable, Identifiable {
    /// One of ``Genres/all``, or ``GenreWall/unclassified``.
    public let name: String

    /// The albums on it, by key, in the order the library had them.
    public let albums: [String]

    public var id: String { name }
}

/// The collection, grouped by the kind of music it is. This is the desktop's `GenreWall`,
/// but it files albums rather than artists. The phone's genre page is a wall of records.
public enum GenreWall {
    /// The card for music that the app cannot file. That is music that is untagged, or
    /// tagged with something that none of the shelves answers to. The name is the desktop's,
    /// and it is shown as it is, like every genre name.
    public static let unclassified = "Other"

    /// The wall: one card for each genre that has an album on it, in the app's order, with
    /// ``unclassified`` last.
    public static func build(_ albums: [CloudAlbum]) -> [GenreWallItem] {
        var filed: [String: [String]] = [:]
        for album in albums {
            filed[genre(of: album), default: []].append(album.key)
        }

        let order = SubgenreTable.shelves.filter { $0 != Genres.unknown } + [unclassified]
        return order.compactMap { name in
            filed[name].map { GenreWallItem(name: name, albums: $0) }
        }
    }

    /// The card that an album is on. This is the genre that most of its tracks are tagged
    /// with, matched to a shelf. A tie goes to the tag that comes first on the record. An
    /// album with no tag, or with a tag that no shelf answers to, is ``unclassified``.
    public static func genre(of album: CloudAlbum) -> String {
        var counts: [String: Int] = [:]
        var first: [String] = []
        for track in album.tracks {
            guard let tag = track.tags?.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tag.isEmpty else { continue }
            if counts[tag] == nil { first.append(tag) }
            counts[tag, default: 0] += 1
        }

        // The count must be strictly higher, so a tie keeps the tag that came first.
        var most: String?
        for tag in first where most == nil || counts[tag, default: 0] > counts[most!, default: 0] {
            most = tag
        }
        return Genres.match(most) ?? unclassified
    }
}

/// The genres wall, built once per library rather than once per drawing of the screen. It
/// uses the same kind of cache as ``ReadArtists``, and the app shell holds it for the same reason.
public final class ReadGenres {
    /// How many times the wall has been built. Tests use this to check that the wall is cached.
    public private(set) var builds = 0

    private var asked: [CloudAlbum] = []
    private var wall: [GenreWallItem] = []

    /// The page for one genre, kept beside the wall it came from. The page is asked for on
    /// every pass of the page's body. Counting every act's albums for the genre is slow, so
    /// it is done once per genre, not on every pass.
    private var whose: String?
    private var page: GenreShelves?

    public init() {}

    /// The wall for this library.
    public func genres(_ albums: [CloudAlbum]) -> [GenreWallItem] {
        if albums != asked || builds == 0 {
            asked = albums
            wall = GenreWall.build(albums)
            builds += 1
            whose = nil
            page = nil
        }
        return wall
    }

    /// The shelves for one genre, or nil for a genre that is not on the wall.
    public func shelves(of genre: String, in albums: [CloudAlbum], byKey: [String: CloudAlbum],
                        artists: [ArtistWallItem]) -> GenreShelves? {
        let wall = genres(albums)
        if whose == genre, let page { return page }

        guard let item = wall.first(where: { $0.name == genre }) else { return nil }
        let built = GenreShelves.of(item, wall: wall, albums: byKey, artists: artists)
        whose = genre
        page = built
        return built
    }
}

// ── one genre's page ──

extension Genres {
    /// A genre as it is said in a sentence. This is the first half of a slashed label, in
    /// lower case, and "R&B" is kept as it is. This is the desktop's `Genres.Spoken`. Like
    /// the genre names, it is not translated.
    public static func spoken(_ genre: String) -> String {
        let head = genre.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? genre
        return head.caseInsensitiveCompare("R&B") == .orderedSame ? "R&B" : head.lowercased()
    }

    /// The genres that stand next to one another, with the head of each family first. This
    /// is the desktop's `Genres.Families`. Change both together.
    private static let families: [[String]] = [
        ["Rock", "Indie", "Punk", "Metal", "Noise"],
        ["Pop", "Indie", "Disco", "Club"],
        ["R&B", "Soul", "Funk", "Disco"],
        ["Hip-Hop / Rap", "Rap", "Trap", "Old School Hip Hop"],
        ["Electronic / Dance", "House", "Techno", "Club"],
        ["Folk", "Country", "Blues"],
        ["Jazz", "Blues", "Avant-Garde"],
        ["Classical", "Neo-Classical", "Opera"],
        ["Soundtrack", "Video Game", "Musical"],
        ["Avant-Garde", "Noise"],
    ]

    /// The genres that this one stands next to. The heads of every family it is in come
    /// first, then the other members of those families, each listed once. This is the
    /// desktop's `Genres.Related`. The result is empty for a genre that is in no family.
    public static func related(_ genre: String) -> [String] {
        var related: [String] = []
        for heads in [true, false] {
            for family in families {
                guard let at = family.firstIndex(where: { $0.caseInsensitiveCompare(genre) == .orderedSame })
                else { continue }
                for (i, name) in family.enumerated() where i != at && heads == (i == 0) {
                    if !related.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                        related.append(name)
                    }
                }
            }
        }
        return related
    }
}

/// Everything that one genre's page shows, built in one pass over the library.
public struct GenreShelves: Sendable, Equatable {
    /// The genre's albums, by key, in the library's order.
    public let albums: [String]

    /// The newest of them, newest first. Twenty at most.
    public let added: [String]

    /// The acts with the most albums in this genre, most first. Twelve at most.
    public let acts: [ArtistWallItem]

    /// How many acts have an album in this genre. This is shown on the line under the name.
    public let actCount: Int

    /// The related genres that the collection holds, with how many albums each one has.
    /// Only genres with albums are listed.
    public let related: [Relation]

    /// The albums by decade, oldest decade first. The newest album comes first within each
    /// decade. Albums with no year are in none of them.
    public let eras: [Era]

    public struct Relation: Sendable, Equatable {
        public let genre: String
        public let albums: Int
    }

    public struct Era: Sendable, Equatable {
        /// The decade's first year: 1970.
        public let decade: Int
        public let albums: [String]
    }

    public static let most = (added: 20, acts: 12)

    /// - Parameters:
    ///   - genre: the genre's card on the wall.
    ///   - wall: the whole wall, used for the counts of the related genres.
    ///   - albums: every album, by key.
    ///   - artists: the artists wall. Its boxes are the notable acts.
    public static func of(_ genre: GenreWallItem, wall: [GenreWallItem],
                          albums: [String: CloudAlbum], artists: [ArtistWallItem]) -> GenreShelves {
        let records = genre.albums.compactMap { albums[$0] }
        let keys = Set(genre.albums)

        let added = records
            .map { (key: $0.key, at: AlbumSort.addedOf($0.tracks)) }
            .filter { $0.at > 0 }
            .sorted { $0.at > $1.at }
            .prefix(most.added)
            .map(\.key)

        // Counted for this genre only, not across the collection. An act with four hundred
        // rock songs and two jazz records is not who the jazz page is about.
        let counted = artists.compactMap { artist -> (ArtistWallItem, Int)? in
            let here = artist.own.filter(keys.contains).count
            return here > 0 ? (artist, here) : nil
        }
        let acts = counted
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                if a.0.tracks != b.0.tracks { return a.0.tracks > b.0.tracks }
                return a.0.name.localizedCaseInsensitiveCompare(b.0.name) == .orderedAscending
            }
            .prefix(most.acts)
            .map(\.0)

        let sizes = Dictionary(wall.map { ($0.name, $0.albums.count) }, uniquingKeysWith: { a, _ in a })
        let related = Genres.related(genre.name).compactMap { name in
            sizes[name].map { Relation(genre: name, albums: $0) }
        }

        var byDecade: [Int: [(key: String, year: Int)]] = [:]
        for record in records {
            let year = AlbumSort.yearOf(record.tracks)
            guard year > 0 else { continue }
            byDecade[year / 10 * 10, default: []].append((record.key, year))
        }
        let eras = byDecade.keys.sorted().map { decade in
            Era(decade: decade,
                albums: byDecade[decade]!.sorted { $0.year > $1.year }.map(\.key))
        }

        return GenreShelves(albums: genre.albums, added: Array(added), acts: Array(acts),
                            actCount: counted.count, related: related, eras: eras)
    }
}

extension Genres {
    /// Every one of the app's genres that a record's tracks are tagged with, in the order in
    /// which they are first met.
    ///
    /// The desktop reads a record in the same way for its home rows and its Similar albums
    /// row (`HomeView.ReadTraits`, `AlbumDetailView.ReadShelfTraits`). Each tag goes through
    /// ``match(_:)``. A tag that matches nothing is dropped, rather than kept as itself.
    /// Keeping it as itself would split "Hip Hop" and "hip-hop" into two genres, and two
    /// records with the same typo would count as alike.
    ///
    /// - Parameter readings: tags that have already been matched. Pass the same dictionary
    ///   across a whole shelf, so that a spelling carried by a thousand tracks is matched once.
    public static func of(_ tracks: [CloudTrack], readings: inout [String: String?]) -> [String] {
        var genres: [String] = []

        for track in tracks {
            guard let tag = track.tags?.genre else { continue }

            let genre: String?
            if let known = readings[tag] {
                genre = known
            } else {
                genre = match(tag)
                readings[tag] = genre
            }

            if let genre, !genres.contains(genre) {
                genres.append(genre)
            }
        }

        return genres
    }
}
