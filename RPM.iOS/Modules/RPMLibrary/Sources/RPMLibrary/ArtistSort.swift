import Foundation
import RPMKit

/// The orders a wall of artists can be put in.
///
/// Persisted by name, for the reason ``AlbumOrdering`` is: stored as a number, inserting
/// an ordering would silently re-point everybody's saved choice at its neighbour.
///
/// The desktop's artists wall has one order and an index rail down the side of it, so
/// these are the phone's own. A rail wants a wall that is always alphabetical; a phone
/// has no room for one, and what it has instead is a way of asking a different question
/// of the same wall.
public enum ArtistOrdering: String, Sendable, CaseIterable, Codable {
    /// Alphabetical, which is the desktop's only order and the default here.
    case name = "Name"

    /// Most records first: who this collection is actually a collection of.
    case albums = "Albums"

    /// Most songs first. A different answer from the records on a library holding one
    /// artist's forty-track anthology and another's six albums of four.
    case tracks = "Tracks"

    /// Most recently added first: who has arrived lately.
    case added = "Added"
}

/// Putting a wall of artists in an order somebody asked for.
///
/// Beside ``AlbumSort`` rather than inside the page, and for the same reason: every one
/// of these has a tie to break and a missing value to place, and those are the parts that
/// go silently wrong. Each order falls back to the name order, so a wall never reshuffles
/// between two runs that agree.
public enum ArtistSort {
    /// The wall in `ordering`.
    ///
    /// - Parameter albums: every album in the library by its key, which is what the
    ///   arrival of an artist has to be read out of. **Not optional**: an ordering that
    ///   quietly could not date anybody would fall back to name order and say nothing,
    ///   and "recently added" is exactly the order nobody checks. Pass
    ///   ``ReadArtists/albums(_:)``, which is the same lookup the pages use.
    public static func by(
        _ artists: [ArtistWallItem], _ ordering: ArtistOrdering, albums: [String: CloudAlbum]
    ) -> [ArtistWallItem] {
        // Read once per artist rather than once per comparison: arrival is a walk of
        // every track on every record of theirs, and a comparison sort would do it a few
        // thousand times over. Which letter they file under is read once for the same
        // reason, since every order falls back to it.
        let wall = artists.map {
            Seat(artist: $0, last: $0.initial == "#",
                 arrived: ordering == .added ? arrival(of: $0, in: albums) : 0)
        }

        return wall.sorted { a, b in
            switch ordering {
            case .albums:
                let mine = a.artist.own.count, theirs = b.artist.own.count
                if mine != theirs { return mine > theirs }

            case .tracks:
                if a.artist.tracks != b.artist.tracks { return a.artist.tracks > b.artist.tracks }

            case .added:
                // Newest first, which puts an artist nothing of whose records can be
                // dated at the end on its own: zero is the smallest arrival there is.
                // That is the right place for them: undated is not old, it is unknown.
                if a.arrived != b.arrived { return a.arrived > b.arrived }

            case .name:
                break
            }

            return byName(a, b)
        }
        .map(\.artist)
    }

    /// The wall in the rail's order: the hash bucket last, then by name the way the
    /// reader's own language compares names.
    ///
    /// What ``ArtistWall/build(_:)`` hands back, so the two cannot disagree about what
    /// alphabetical means, and what every other ordering above falls back to.
    public static func byName(_ artists: [ArtistWallItem]) -> [ArtistWallItem] {
        artists
            .map { Seat(artist: $0, last: $0.initial == "#", arrived: 0) }
            .sorted(by: byName)
            .map(\.artist)
    }

    /// When an artist arrived: the newest of their own records.
    ///
    /// Their own, not everything they turn up on. A guest verse on a compilation somebody
    /// uploaded this morning is not that artist arriving in the collection, and reading
    /// appearances would put every act on every recent compilation at the head of the
    /// wall.
    ///
    /// Zero where nothing of theirs can be dated, which is a stated answer: the sort
    /// places those at the end rather than at whichever end a zero happens to fall.
    public static func arrival(of artist: ArtistWallItem, in albums: [String: CloudAlbum]) -> Int64 {
        artist.own
            .compactMap { albums[$0] }
            .reduce(Int64(0)) { max($0, AlbumSort.addedOf($1.tracks)) }
    }

    /// One artist with the two facts every order needs read off them already.
    private struct Seat {
        let artist: ArtistWallItem

        /// Whether they file under the rail's bucket rather than under a letter. Every
        /// culture sorts digits and symbols in front of letters, so left to a plain sort
        /// the numbers would be at the top and the rail would be lying about where they
        /// are.
        let last: Bool

        let arrived: Int64
    }

    private static func byName(_ one: Seat, _ other: Seat) -> Bool {
        if one.last != other.last { return other.last }

        let order = one.artist.name.compare(other.artist.name, options: .caseInsensitive,
                                            range: nil, locale: .current)
        if order != .orderedSame { return order == .orderedAscending }

        // A stated tiebreak, so two builds over one collection cannot disagree about the
        // order of two names that differ only in case.
        return one.artist.name < other.artist.name
    }
}
