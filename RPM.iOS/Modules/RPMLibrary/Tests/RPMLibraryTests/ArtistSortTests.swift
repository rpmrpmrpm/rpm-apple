import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The orders the phone's artist wall can use. The desktop has one order and an index rail. These
/// orders exist only on the phone, so each one is tested here, not against a desktop test.

private func track(_ id: String, artist: String?, added: Int64) -> CloudTrack {
    CloudTrack(rpmId: id, artist: artist, addedAt: added)
}

private func album(_ key: String, _ name: String, _ artist: String,
                   songs: Int = 1, added: Int64 = 0) -> CloudAlbum {
    CloudAlbum(key: key, album: name, artist: artist,
               tracks: (0..<songs).map { track("\(key)#\($0)", artist: artist, added: added) })
}

private func wall(_ albums: [CloudAlbum], _ ordering: ArtistOrdering) -> [String] {
    let byKey = Dictionary(uniqueKeysWith: albums)
    return ArtistSort.by(ArtistWall.build(ArtistWall.rows(albums)), ordering, albums: byKey)
        .map(\.name)
}

private extension Dictionary where Key == String, Value == CloudAlbum {
    init(uniqueKeysWith albums: [CloudAlbum]) {
        self.init(uniqueKeysWithValues: albums.map { ($0.key, $0) })
    }
}

@Suite struct ArtistSortTests {
    private let library = [
        album("a", "One", "Prince", songs: 4, added: 100),
        album("b", "Two", "Prince", songs: 4, added: 200),
        album("c", "Three", "ABBA", songs: 20, added: 900),
        album("d", "Four", "Zappa", songs: 2, added: 50),
    ]

    /// The default order. It is also the desktop's only order.
    @Test func nameOrderIsTheRailsOrder() {
        #expect(wall(library, .name) == ["ABBA", "Prince", "Zappa"])
    }

    /// Artists with the most records come first.
    @Test func mostRecordsFirst() {
        #expect(wall(library, .albums) == ["Prince", "ABBA", "Zappa"])
    }

    /// Counts songs, not records. One artist's twenty-track anthology outweighs another artist's two
    /// albums of four tracks.
    @Test func mostSongsFirst() {
        #expect(wall(library, .tracks) == ["ABBA", "Prince", "Zappa"])
    }

    /// Artists whose newest record was added most recently come first.
    @Test func newestArrivalFirst() {
        #expect(wall(library, .added) == ["ABBA", "Prince", "Zappa"])
    }

    /// An artist with no dated records goes last. No date means unknown, not old. Otherwise a library
    /// uploaded before the date field existed would always lead the wall.
    @Test func anArtistNothingCanDateReadsLast() {
        let dated = [
            album("a", "One", "Undated", added: 0),
            album("b", "Two", "Recent", added: 500),
            album("c", "Three", "Older", added: 100),
        ]

        #expect(wall(dated, .added) == ["Recent", "Older", "Undated"])
    }

    /// An artist who appears on a new compilation has not arrived. Arrival comes only from the artist's
    /// own records.
    @Test func anAppearanceIsNotAnArrival() {
        let albums = [
            album("a", "Parklife", "Blur", added: 100),
            CloudAlbum(key: "b", album: "Now 40", artist: "Various Artists",
                       tracks: [track("b#0", artist: "Blur", added: 900),
                                track("b#1", artist: "Pulp", added: 900)]),
            album("c", "Different Class", "Pulp", added: 200),
        ]

        // The compilation was added today and has both artists on it. Neither artist arrived today:
        // Pulp's own record is newer than Blur's, so Pulp comes first. The compilations shelf is what
        // arrived, so it leads the wall.
        #expect(wall(albums, .added) == [ArtistWall.compilations, "Pulp", "Blur"])
    }

    /// Every order falls back to name order when values are equal, so the wall gives the same result
    /// each time.
    @Test(arguments: ArtistOrdering.allCases)
    func tiesFallBackToTheName(ordering: ArtistOrdering) {
        let tied = [
            album("a", "One", "Zappa", songs: 3, added: 100),
            album("b", "Two", "ABBA", songs: 3, added: 100),
            album("c", "Three", "Madonna", songs: 3, added: 100),
        ]

        #expect(wall(tied, ordering) == ["ABBA", "Madonna", "Zappa"])
    }

    /// The rail's last bucket (here, the name "2Pac") stays last in every order. The tie-break uses the
    /// rail's order, not a plain name comparison.
    @Test func theBucketStaysLastUnderEveryOrder() {
        let mixed = [
            album("a", "One", "2Pac", songs: 3, added: 100),
            album("b", "Two", "Madonna", songs: 3, added: 100),
        ]

        for ordering in ArtistOrdering.allCases {
            #expect(wall(mixed, ordering) == ["Madonna", "2Pac"])
        }
    }

    /// A record by two artists counts for both of them. It is in both their counts and both their
    /// arrivals.
    @Test func aJointRecordCountsForBoth() {
        let albums = [
            album("a", "Graduation", "Kanye West", songs: 1, added: 100),
            album("b", "Be", "Common", songs: 1, added: 100),
            album("c", "Both", "Kanye West & Common", songs: 1, added: 900),
        ]

        // Two records each, and the joint one is the newest thing either of them has.
        #expect(wall(albums, .albums) == ["Common", "Kanye West"])
        #expect(wall(albums, .added) == ["Common", "Kanye West"])
    }
}
