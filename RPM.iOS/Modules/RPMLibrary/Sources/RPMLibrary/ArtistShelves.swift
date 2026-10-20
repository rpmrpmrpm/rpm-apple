import Foundation
import RPMKit

/// What an artist's page holds: their records sorted onto shelves, and every song of
/// theirs the collection has.
///
/// The shelving rule is the desktop's `ArtistDetailView.ShelvesAsync`, lifted out of the
/// view because it is a set of decisions and a decision inside a layout pass is a decision
/// nothing can check.
public struct ArtistShelves: Sendable, Equatable {
    /// Records they made: their own, less whatever their names say belongs elsewhere.
    public let records: [CloudAlbum]

    /// Records they made with somebody, same subtraction.
    public let together: [CloudAlbum]

    public let eps: [CloudAlbum]
    public let live: [CloudAlbum]
    public let mixtapes: [CloudAlbum]
    public let soundtracks: [CloudAlbum]
    public let compilations: [CloudAlbum]
    public let singles: [CloudAlbum]

    /// Somebody else's records they turn up on. Not sorted by kind: what is being shown
    /// is which records those are, and the name on the sleeve is not a claim about this
    /// artist at all.
    public let appearances: [CloudAlbum]

    /// Every song of theirs, their own records first. One entry per track, with the
    /// record it came off.
    public let songs: [ArtistSong]

    /// Whether there is nothing at all to draw.
    public var isEmpty: Bool {
        records.isEmpty && together.isEmpty && eps.isEmpty && live.isEmpty && mixtapes.isEmpty
            && soundtracks.isEmpty
            && compilations.isEmpty && singles.isEmpty && appearances.isEmpty
    }

    /// One song on the artist's listing: the track, and the record it is on.
    public struct ArtistSong: Sendable, Equatable, Identifiable {
        public let track: CloudTrack
        public let album: CloudAlbum

        /// The track's own id, and it is unique across the listing: a record appears on
        /// one shelf only, so no track is gathered twice.
        public var id: String { track.rpmId }
    }

    /// The page for one artist, over the albums the wall was built from.
    ///
    /// - Parameter albums: every album in the library, keyed the way ``ArtistWall/rows(_:)``
    ///   keyed them.
    public static func of(_ artist: ArtistWallItem, in albums: [String: CloudAlbum]) -> ArtistShelves {
        func found(_ keys: [String]) -> [CloudAlbum] { keys.compactMap { albums[$0] } }

        let own = found(artist.own)

        // One record, one shelf: the type the record's files carry, else what its name
        // suggests (``ReleaseType/shelf(of:)``). A name that answers more than once is read
        // most particular first, so "Live at Abbey Road - Single" is a single and none of
        // them is listed twice.
        func kind(_ type: ReleaseType) -> [CloudAlbum] {
            newestFirst(own.filter { ReleaseType.shelf(of: $0) == type })
        }
        func ordinary(_ album: CloudAlbum) -> Bool { ReleaseType.shelf(of: album) == .album }

        return ArtistShelves(
            records: newestFirst(found(artist.albums).filter(ordinary)),
            together: newestFirst(found(artist.together).filter(ordinary)),
            eps: kind(.ep),
            live: kind(.live),
            mixtapes: kind(.mixtape),
            soundtracks: kind(.soundtrack),
            compilations: kind(.compilation),
            singles: kind(.single),
            appearances: newestFirst(found(artist.appearances)),
            songs: songs(of: artist, own: own, appearances: found(artist.appearances)))
    }

    /// One shelf, newest record first.
    ///
    /// By year rather than by name: a shelf that reads alphabetically puts a b-sides
    /// compilation in front of the record that made the artist, and there is nothing to
    /// be learnt from the first letter of an album's name. Read from the top, this is their
    /// discography in reverse, which is what somebody opening an artist usually wants.
    ///
    /// A record with no year at all goes to the end rather than to whichever end a zero
    /// sorts to. An untagged record is not the artist's newest and it is not their oldest
    /// either; what it is, is unknown. Ties fall back to their names, so the shelf is the
    /// same shelf every time it is built.
    private static func newestFirst(_ albums: [CloudAlbum]) -> [CloudAlbum] {
        albums
            .map { (year: AlbumSort.yearOf($0.tracks), album: $0) }
            .sorted { left, right in
                let leftDated = left.year > 0, rightDated = right.year > 0
                if leftDated != rightDated { return leftDated }
                if left.year != right.year { return left.year > right.year }

                let order = left.album.album.compare(right.album.album, options: .caseInsensitive,
                                                     range: nil, locale: .current)
                if order != .orderedSame { return order == .orderedAscending }
                return left.album.key < right.album.key
            }
            .map(\.album)
    }

    /// Every song of theirs.
    ///
    /// Their own records whole, because every track on a record of theirs is theirs
    /// whatever the credit says: a track with no artist tag at all is still on their
    /// album. Somebody else's record is filtered to the tracks that name them, which is
    /// the whole reason it is on the page.
    ///
    /// Records they made with somebody count as their own here, where the desktop reads
    /// only ``ArtistWallItem/albums``. A joint record is theirs, and half its tracks are
    /// credited to the pair rather than to either of them, so filtering it would drop
    /// songs off the page of both artists who made it.
    private static func songs(
        of artist: ArtistWallItem, own: [CloudAlbum], appearances: [CloudAlbum]
    ) -> [ArtistSong] {
        var songs: [ArtistSong] = []

        for album in own {
            songs += album.tracks.map { ArtistSong(track: $0, album: album) }
        }

        for album in appearances {
            songs += album.tracks
                .filter { ArtistWall.names($0.artist, artist: artist.name) }
                .map { ArtistSong(track: $0, album: album) }
        }

        return songs
    }
}
