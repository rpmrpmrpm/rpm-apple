import Foundation
import RPMKit

/// A genre's popular songs, from how often each has been listened to across everybody's listening,
/// over the whole genre rather than one act (``ArtistPopular``'s rules). The
/// Android `GenrePopular.kt`, rule for rule.
///
/// The world's plays are asked per record, so a genre of hundreds of records is asked about its
/// ``asked`` most played here; and so one famous act does not fill the list, each act keeps at most
/// ``perAct`` songs in it.
public enum GenrePopular {
    /// How many of the genre's records are asked about.
    public static let asked = 40

    /// The most songs one act (a record's album artist) has in the list.
    public static let perAct = 3

    /// The records to ask about: the ones played most here first, then in the genre's order.
    public static func records(_ albums: [CloudAlbum], playsOf: (CloudAlbum) -> Int) -> [CloudAlbum] {
        let counted = albums.enumerated().map { (at: $0.offset, album: $0.element, plays: playsOf($0.element)) }
        return counted
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.at < $1.at }
            .prefix(asked)
            .map(\.album)
    }

    /// Every song of `records`, each with its record: what ``ranked(_:plays:)`` ranks.
    public static func songs(_ records: [CloudAlbum]) -> [ArtistShelves.ArtistSong] {
        records.flatMap { album in album.tracks.map { ArtistShelves.ArtistSong(track: $0, album: album) } }
    }

    /// The songs by listens, most first, ``ArtistPopular``'s way (one per title, half of the songs at
    /// most), with no act past ``perAct``, at most ``ArtistPopular/most``. Empty where fewer than
    /// ``ArtistPopular/fewest`` are left.
    public static func ranked(_ songs: [ArtistShelves.ArtistSong],
                              plays: [String: [TrackPlace: Int64]]) -> [ArtistShelves.ArtistSong] {
        var perActHeld: [String: Int] = [:]
        let kept = ArtistPopular.ranked(songs, plays: plays, most: .max).filter { song in
            let act = NameMatch.squash(song.album.artist)
            let had = perActHeld[act] ?? 0
            guard had < perAct else { return false }
            perActHeld[act] = had + 1
            return true
        }
        let listed = Array(kept.prefix(ArtistPopular.most))
        return listed.count >= ArtistPopular.fewest ? listed : []
    }
}
