import Foundation
import RPMKit

/// The orders of the records' list view.
///
/// Stored by name, like ``AlbumOrdering``, so a new order added later does not move anybody's saved
/// choice onto its neighbour.
public enum ListOrdering: String, Sendable, CaseIterable, Codable {
    /// Each record with its songs, by whose record it is, then by its name.
    case artist = "Artist"

    /// Each record with its songs, by the record's own name.
    case album = "Album"

    /// Every song as its own row, by its title.
    case track = "Track"
}

/// The records as one list, for the phone's list view of the library. It joins the desktop's last two
/// views: the album list, where each record stands with its songs under it, and the data table, which
/// can be put in another order. Ordered by artist or by record, each record is one block with its songs.
/// Ordered by track, every song is a row of its own, by title.
///
/// **The letter comes first in the order, then the name**, as on the desktop's artists wall
/// (``ArtistWall/initial(_:)``). The letter skips a name's leading punctuation, and a plain sort by
/// name does not. So "(hed) p.e." is filed under H, and a sort by name alone would put it ahead of
/// every A: the rail's letters would then run H, A, B down the list, and a press on A would land
/// under H. Names with no letter of the rail (digits, symbols, other scripts) are filed under "#",
/// which is last, as on the rail.
public struct AlbumListing: Sendable, Equatable {
    /// One row of the list.
    public enum Row: Sendable, Identifiable, Equatable {
        /// A record, drawn with its songs under it.
        case record(CloudAlbum)

        /// One song, in track order, and the record it is on.
        case song(CloudTrack, on: CloudAlbum)

        public var id: String {
            switch self {
            case .record(let album): "record:\(album.key)"
            case .song(let track, let album): "song:\(album.key)/\(track.rpmId)"
            }
        }
    }

    public let rows: [Row]

    /// The first row filed under each letter of the rail, by row id. A letter that is not here has
    /// nothing under it.
    public let firstUnder: [Character: String]

    public static let empty = AlbumListing(rows: [], firstUnder: [:])

    /// Builds the list. It reads every song in track order, so a caller with a large library runs it
    /// away from the main thread.
    public static func of(_ albums: [CloudAlbum], by order: ListOrdering) -> AlbumListing {
        var filed: [(place: Place, row: Row)] = []

        switch order {
        case .artist:
            filed = albums.map { (Place(albums: $0.artist, then: [$0.album]), .record($0)) }

        case .album:
            filed = albums.map { (Place(albums: $0.album, then: [$0.artist]), .record($0)) }

        case .track:
            filed.reserveCapacity(albums.reduce(0) { $0 + $1.tracks.count })
            for album in albums {
                for track in album.tracks {
                    let place = Place(albums: track.title ?? "",
                                      then: [track.artist ?? album.artist, album.album],
                                      disc: track.tags?.discNumber ?? 0,
                                      number: track.tags?.trackNumber ?? 0)
                    filed.append((place, .song(track, on: album)))
                }
            }
        }

        filed.sort { $0.place < $1.place }

        var firstUnder: [Character: String] = [:]
        for entry in filed where firstUnder[entry.place.letter] == nil {
            firstUnder[entry.place.letter] = entry.row.id
        }

        return AlbumListing(rows: filed.map(\.row), firstUnder: firstUnder)
    }

    /// Where a row goes: its letter on the rail, then its name, then the names that break a tie, read
    /// once per row and not once per comparison.
    private struct Place: Comparable {
        let letter: Character
        let names: [String]
        let disc: Int
        let number: Int

        init(albums name: String, then ties: [String], disc: Int = 0, number: Int = 0) {
            letter = ArtistWall.initial(name)
            names = ([name] + ties).map(Self.folded)
            self.disc = disc
            self.number = number
        }

        /// Case and accents do not count: "Émilie" sits with "Emilie", as the rail files it.
        private static func folded(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                         locale: nil)
        }

        static func < (a: Place, b: Place) -> Bool {
            // "#" after Z, whatever its character sorts as.
            let aLast = a.letter == "#", bLast = b.letter == "#"
            if aLast != bLast { return bLast }
            if a.letter != b.letter { return a.letter < b.letter }
            if a.names != b.names { return a.names.lexicographicallyPrecedes(b.names) }
            if a.disc != b.disc { return a.disc < b.disc }
            return a.number < b.number
        }

        static func == (a: Place, b: Place) -> Bool {
            a.letter == b.letter && a.names == b.names && a.disc == b.disc && a.number == b.number
        }
    }
}
