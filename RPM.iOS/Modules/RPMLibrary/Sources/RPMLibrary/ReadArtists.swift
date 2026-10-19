import Foundation
import RPMKit

/// The collection grouped by artist, **built once**. The screen does not rebuild it
/// each time the view is drawn.
///
/// This class works the same way as ``SortedWall``, for the same reason. Building the
/// artist wall reads every credit on every track. It splits the credits that name more
/// than one act, decides which of the collection's album artists are collaborations,
/// and sorts the acts in the reader's own language. A SwiftUI body runs whenever
/// anything on the screen moves. If this work were written inside a body, the whole
/// cost would be paid on every pass.
///
/// So the result is kept, and it is returned again whenever the question is the same.
/// The question is the library. Comparing two libraries is cheap, because two Swift
/// arrays that share storage compare in constant time. A view receives the same
/// array on each pass while the library has not changed.
///
/// The object is held by the app shell and passed to the page. It must not be a
/// global. A tab is created when the user opens it and discarded when they leave. A
/// cache owned by the page would therefore be empty on every visit.
public final class ReadArtists {
    /// The number of times the wall has actually been built. This value is used in
    /// tests to check that the cache works. The gap between how often the wall is
    /// asked for and how often it is built shows the cache is working.
    public private(set) var builds = 0

    private var asked: [CloudAlbum] = []
    private var wall: [ArtistWallItem] = []
    private var byKey: [String: CloudAlbum] = [:]

    /// The wall in the order it was last asked for. It is kept next to the wall, not
    /// in place of it, because the two change at different times. The order changes
    /// when the user changes the sort menu. The wall changes when the library does.
    private var ordering: ArtistOrdering?
    private var ordered: [ArtistWallItem] = []

    /// One artist's page, kept beside the wall it came from. Opening an artist and
    /// scrolling their page asks the same question on every pass of the body. Sorting
    /// an artist's records onto shelves runs four regular expressions over every title
    /// they have, so the result is cached.
    private var whose: String?
    private var page: ArtistShelves?

    /// The wall indexed by squashed name. It is built the first time an artist is
    /// looked up by name, and it is dropped along with the wall.
    private var byName: [String: ArtistWallItem]?

    /// The wall indexed by lower-cased album key, listing who claims each record as
    /// their own. It is built the first time an album page asks for it, and it is
    /// dropped along with the wall.
    private var byOwnAlbum: [String: [ArtistWallItem]]?

    public init() {}

    /// Every artist in this library, in the rail's order.
    public func artists(_ albums: [CloudAlbum]) -> [ArtistWallItem] {
        settle(albums)
        return wall
    }

    /// Every artist in this library, in the order that was requested.
    public func artists(_ albums: [CloudAlbum], in ordering: ArtistOrdering) -> [ArtistWallItem] {
        settle(albums)

        if self.ordering == ordering { return ordered }

        self.ordering = ordering
        ordered = ArtistSort.by(wall, ordering, albums: byKey)
        return ordered
    }

    /// Every album in this library, indexed by the key the wall uses for it. A page
    /// uses this to turn an artist's list of keys back into album records.
    public func albums(_ albums: [CloudAlbum]) -> [String: CloudAlbum] {
        settle(albums)
        return byKey
    }

    /// One artist's shelves and songs.
    public func shelves(of artist: ArtistWallItem, in albums: [CloudAlbum]) -> ArtistShelves {
        settle(albums)

        if whose == artist.name, let page { return page }

        let built = ArtistShelves.of(artist, in: byKey)
        whose = artist.name
        page = built
        return built
    }

    /// The artist whose page a track opens. This is the first act in the track's own
    /// credit that has a box on the wall. If none matches, the act the track's album
    /// is filed under is tried.
    ///
    /// The whole credit is tried before its parts. This means a band whose name
    /// contains a separator, such as "Earth, Wind & Fire", is found as one act. Returns
    /// `nil` when no name in the credit has a box. That is the case for a guest who has
    /// no records of their own on the wall.
    public func artist(of track: CloudTrack, in albums: [CloudAlbum]) -> ArtistWallItem? {
        settle(albums)

        let index = byName ?? Dictionary(wall.map { (NameMatch.squash($0.name), $0) },
                                         uniquingKeysWith: { first, _ in first })
        byName = index

        let filedUnder = byKey[AlbumGrouping.key(for: track)]?.artist
        let names = [track.artist] + ArtistCredit.split(track.artist) + [filedUnder]

        for case let name? in names {
            // Every spelling of the compilation marker maps to the same box.
            let key = NameMatch.squash(ArtistCredit.isVariousArtists(name)
                                           ? ArtistWall.compilations : name)
            if !key.isEmpty, let found = index[key] { return found }
        }

        return nil
    }

    /// The artist pages that an album page links to. These are the acts that list the
    /// record as their own, in the order the album's credit names them.
    ///
    /// A record by one act gives one page. A record that two acts made together gives
    /// one page per act. A various-artists record gives the compilations entry. A
    /// guest who appears on one track is not included. The record is shown on that
    /// guest's page as a guest appearance, not as one of their own albums. The result
    /// is empty only when the album is not in `albums`.
    public func artists(of album: CloudAlbum, in albums: [CloudAlbum]) -> [ArtistWallItem] {
        settle(albums)

        let index = byOwnAlbum ?? Self.byOwnAlbum(wall)
        byOwnAlbum = index

        let found = index[album.key.lowercased()] ?? []
        guard found.count > 1 else { return found }

        // The wall is in name order, but the credit is in the order the record names
        // its acts. An act that the credit does not spell out is placed last, in wall
        // order.
        let parts = ArtistCredit.splitWide(album.artist)
        let position = { (item: ArtistWallItem) in
            parts.firstIndex { NameMatch.same($0, item.name) } ?? parts.count
        }

        return found.enumerated()
            .sorted { (position($0.element), $0.offset) < (position($1.element), $1.offset) }
            .map(\.element)
    }

    private static func byOwnAlbum(_ wall: [ArtistWallItem]) -> [String: [ArtistWallItem]] {
        var index: [String: [ArtistWallItem]] = [:]
        for item in wall {
            for key in item.own { index[key.lowercased(), default: []].append(item) }
        }
        return index
    }

    private func settle(_ albums: [CloudAlbum]) {
        guard asked != albums else { return }

        asked = albums
        builds += 1
        wall = ArtistWall.build(ArtistWall.rows(albums))
        byKey = Dictionary(albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        // The library changed, so the cached page may refer to records that no longer
        // exist. The cached order refers to a wall that has been replaced. Everything
        // derived from the old library is cleared.
        whose = nil
        page = nil
        ordering = nil
        ordered = []
        byName = nil
        byOwnAlbum = nil
    }
}
