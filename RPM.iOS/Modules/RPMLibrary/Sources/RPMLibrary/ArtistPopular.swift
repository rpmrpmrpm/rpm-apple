import Foundation
import RPMKit

/// The songs of one artist the world plays most, for the first section of their page.
///
/// The desktop's popular tracks (`LibraryDatabase.QueryPopularUnder`, the genre page's "Popular
/// tracks") ranked over one artist's songs instead of one genre's, from the same counts: how many
/// times ListenBrainz's listeners have played each recording (see ``WorldPlays``).
///
/// **Only where a ranking says something.** The section is a short list of the songs people know,
/// so it is never more than half of what the collection holds of the artist, and it is not drawn
/// with fewer than ``fewest`` songs. An artist with six songs gets no section: their whole listing
/// is already short.
public enum ArtistPopular {
    /// The most songs listed: three panels of four.
    public static let most = 12

    /// Fewer than this and there is no section: less than one panel of four.
    public static let fewest = 4

    /// The most records asked about for one artist. Each is one request, and a first visit to a
    /// record nobody has asked about costs the server several rate-limited catalogue calls.
    public static let asked = 40

    /// The records to ask about: every record one of their songs is on, those holding most of their
    /// songs first, at most ``asked``.
    public static func records(_ songs: [ArtistShelves.ArtistSong]) -> [CloudAlbum] {
        var order: [String] = []
        var albums: [String: CloudAlbum] = [:]
        var count: [String: Int] = [:]

        for song in songs {
            if albums[song.album.key] == nil {
                order.append(song.album.key)
                albums[song.album.key] = song.album
            }
            count[song.album.key, default: 0] += 1
        }

        // Stable: records holding as many of their songs keep the listing's order.
        let ranked = order.enumerated().sorted { a, b in
            let (ca, cb) = (count[a.element] ?? 0, count[b.element] ?? 0)
            return ca != cb ? ca > cb : a.offset < b.offset
        }

        return ranked.prefix(asked).compactMap { albums[$0.element] }
    }

    /// Their songs with the most listens, most first.
    ///
    /// - A song is counted where the record it is on has an answer and its disc and position on
    ///   that record have listens above nought. A song with no track number cannot be matched and
    ///   is left out.
    /// - One song per title: the same song on a studio album, a live album and a compilation is
    ///   listed once, as whichever copy is played most. Bracketed asides ("(Remastered)", "[Live]")
    ///   do not make a title different.
    /// - At most ``most``, and at most half of their songs. Empty where fewer than ``fewest`` are left.
    ///
    /// - Parameter plays: the listens of each record, keyed by the record's key.
    public static func ranked(_ songs: [ArtistShelves.ArtistSong],
                              plays: [String: [TrackPlace: Int64]]) -> [ArtistShelves.ArtistSong] {
        ranked(songs, plays: plays, most: most)
    }

    /// The same ranking with another limit than ``most``: a genre's ranks every song before it caps
    /// each act (``GenrePopular``).
    static func ranked(_ songs: [ArtistShelves.ArtistSong], plays: [String: [TrackPlace: Int64]],
                       most: Int) -> [ArtistShelves.ArtistSong] {
        let counted: [(song: ArtistShelves.ArtistSong, listens: Int64)] = songs.compactMap { song in
            let position = Int(AlbumGrouping.track(of: song.track))
            guard position > 0, let record = plays[song.album.key] else { return nil }

            let disc = max(1, Int(AlbumGrouping.disc(of: song.track)))
            guard let listens = record[TrackPlace(disc: disc, position: position)], listens > 0 else {
                return nil
            }
            return (song, listens)
        }

        let ordered = counted.sorted { a, b in
            if a.listens != b.listens { return a.listens > b.listens }
            return a.song.id < b.song.id
        }

        var titles: Set<String> = []
        let distinct = ordered.filter { titles.insert(title(of: $0.song.track)).inserted }.map(\.song)

        let room = min(most, songs.count / 2)
        let listed = Array(distinct.prefix(room))
        return listed.count >= fewest ? listed : []
    }

    /// A title as compared for sameness: lowercased, trimmed, bracketed asides removed.
    static func title(of track: CloudTrack) -> String {
        var text = (track.title ?? "").lowercased()
        while let open = text.firstIndex(where: { $0 == "(" || $0 == "[" }) {
            let close: Character = text[open] == "(" ? ")" : "]"
            guard let end = text[open...].firstIndex(of: close) else { break }
            text.removeSubrange(open...end)
        }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? (track.title ?? "").lowercased() : plain
    }
}
