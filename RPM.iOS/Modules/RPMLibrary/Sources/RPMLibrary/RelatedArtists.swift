import Foundation
import RPMKit

/// The acts in this collection closest to one act, for the artist page. The
/// Android `RelatedArtists.kt`, rule for rule.
///
/// Read from the collection alone, as no service of the app's says who is related to whom: an act
/// credited on a record with them counts most (``together`` a record), then how much of their music
/// is of the same genres (the share of each act's records on each genre shelf, overlapped: 1 for two
/// acts whose records are shelved alike, 0 for none in common). A record on no shelf
/// (``GenreWall/unclassified``) may still carry a genre tag no shelf answers to; the same overlap of
/// those tags as written (a record's most common one) counts too. And the lists they share,
/// playlists and mood lists, each counting for as few acts as it holds (a list of three says more
/// than one of thirty): the share of the act's own lists' weight the other is on. The closest of the
/// three is taken.
///
/// An act with nothing in common, by records or by at least ``leastAlike`` of genre, is not related.
/// Various Artists is never one. At most ``most``, closest first; ties go to the act with more songs,
/// then by name.
public enum RelatedArtists {
    public static let most = 12

    /// What one record made together counts, against a genre overlap of at most 1.
    public static let together = 2.0

    /// The genre overlap an act needs without a record in common.
    public static let leastAlike = 0.5

    /// What the rule reads: every act, the genre shelves, the records by key, and the tracks of every
    /// list (playlists and mood lists).
    public struct Collection: Sendable {
        public let artists: [ArtistWallItem]
        public let genres: [GenreWallItem]
        public let albums: [String: CloudAlbum]
        public let lists: [[CloudTrack]]

        public init(artists: [ArtistWallItem], genres: [GenreWallItem],
                    albums: [String: CloudAlbum], lists: [[CloudTrack]]) {
            self.artists = artists
            self.genres = genres
            self.albums = albums
            self.lists = lists
        }
    }

    public static func of(_ artist: ArtistWallItem, in collection: Collection) -> [ArtistWallItem] {
        var shelfOf: [String: String] = [:]
        for genre in collection.genres where genre.name != GenreWall.unclassified {
            for key in genre.albums { shelfOf[key] = genre.name }
        }

        var tagOf: [String: String] = [:]
        for (key, album) in collection.albums {
            if let tag = tag(of: album) { tagOf[key] = tag }
        }

        let mine = Set(artist.own + artist.appearances)
        let myShares = shares(artist.own, shelfOf)
        let myTags = shares(artist.own, tagOf)
        let me = NameMatch.squash(artist.name)
        let listed = listShares(me, collection)

        let scored: [(act: ArtistWallItem, score: Double)] = collection.artists.compactMap { other in
            let them = NameMatch.squash(other.name)
            guard them != me, !ArtistCredit.isVariousArtists(other.name) else { return nil }

            let together = (other.own + other.appearances).filter { mine.contains($0) }.count
            let alike = max(overlap(myShares, shares(other.own, shelfOf)),
                            overlap(myTags, shares(other.own, tagOf)),
                            listed[them] ?? 0)
            guard together > 0 || alike >= leastAlike else { return nil }
            return (other, Double(together) * Self.together + alike)
        }

        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.act.tracks != $1.act.tracks { return $0.act.tracks > $1.act.tracks }
                return $0.act.name < $1.act.name
            }
            .prefix(most)
            .map(\.act)
    }

    /// For every other act, the share of `me`'s list weight they are on: each list `me` is on weighs
    /// one over the number of acts on it, and an act on all of them has 1. An act is on a list when
    /// one of their own records holds one of its songs.
    private static func listShares(_ me: String, _ collection: Collection) -> [String: Double] {
        var owners: [String: Set<String>] = [:]
        for act in collection.artists {
            let name = NameMatch.squash(act.name)
            for key in act.own { owners[key, default: []].insert(name) }
        }

        var albumOf: [String: String] = [:]
        for album in collection.albums.values {
            for track in album.tracks { albumOf[track.rpmId] = album.key }
        }

        var total = 0.0
        var shared: [String: Double] = [:]
        for list in collection.lists {
            var acts = Set<String>()
            for track in list {
                if let key = albumOf[track.rpmId], let names = owners[key] { acts.formUnion(names) }
            }
            guard acts.contains(me), acts.count >= 2 else { continue }

            let weight = 1.0 / Double(acts.count)
            total += weight
            for act in acts where act != me { shared[act, default: 0] += weight }
        }

        guard total > 0 else { return [:] }
        return shared.mapValues { $0 / total }
    }

    /// A record's genre tag as written, the one most of its tracks carry, folded to lower case; nil
    /// for none. On a tie, the first in alphabetical order.
    static func tag(of album: CloudAlbum) -> String? {
        var counts: [String: Int] = [:]
        for track in album.tracks {
            guard let genre = track.tags?.genre?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(), !genre.isEmpty else { continue }
            counts[genre, default: 0] += 1
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
    }

    /// The share of `albums` on each genre shelf (or tag); albums with none are left out of the count.
    private static func shares(_ albums: [String], _ shelfOf: [String: String]) -> [String: Double] {
        let shelved = albums.compactMap { shelfOf[$0] }
        guard !shelved.isEmpty else { return [:] }

        var counts: [String: Int] = [:]
        for shelf in shelved { counts[shelf, default: 0] += 1 }
        return counts.mapValues { Double($0) / Double(shelved.count) }
    }

    /// How much two shares have in common: the sum, over each shelf, of the smaller share.
    private static func overlap(_ a: [String: Double], _ b: [String: Double]) -> Double {
        a.reduce(0) { sum, entry in sum + min(entry.value, b[entry.key] ?? 0) }
    }
}
