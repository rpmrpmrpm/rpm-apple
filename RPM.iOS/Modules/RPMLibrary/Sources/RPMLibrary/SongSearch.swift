import Foundation
import RPMKit

/// Finds songs in a library from text typed by the user.
///
/// The library tab's search and the playlist song picker both use this code. Keeping
/// one copy of the matching rule means the two searches always give the same results.
public enum SongSearch {
    /// One song found by a search, together with the album it belongs to.
    ///
    /// **This is a struct, not a tuple.** A list needs a stable identity for each row,
    /// and a tuple has none. The album is stored in the hit. Looking it up again for
    /// each row would scan the whole library once per row. That is slow for a library
    /// of about three thousand albums.
    public struct SongHit: Sendable, Equatable, Identifiable {
        public let track: CloudTrack
        public let album: CloudAlbum

        public var id: String { track.rpmId }

        public init(track: CloudTrack, album: CloudAlbum) {
            self.track = track
            self.album = album
        }
    }

    /// The maximum number of rows one search returns.
    ///
    /// A library can hold tens of thousands of songs, and a phone shows only about
    /// eight rows at a time. Three hundred rows is too many for a user to scan. If a
    /// search gives that many results, the user needs a more specific search term, not
    /// a longer list.
    public static let ceiling = 300

    /// Checks whether a song matches the text: its title, its artist, or its album,
    /// ignoring case.
    ///
    /// The album's artist is checked as well as the track's artist. A compilation
    /// credits a different artist on the album than on each track, so both names must
    /// be checked.
    public static func matches(_ track: CloudTrack, on album: CloudAlbum, _ asking: String) -> Bool {
        has(album.album, asking) || has(album.artist, asking)
            || has(track.title, asking) || has(track.artist, asking)
    }

    /// Checks one field against the search text, after lowercasing the field. **No
    /// temporary arrays are built.**
    ///
    /// The four fields are checked one at a time. Building an array of them would
    /// allocate memory for every song. It would also lowercase all four strings, even
    /// when the first one already matched. For a library of about seventeen thousand
    /// songs, that is seventeen thousand arrays and close to seventy thousand lowercased
    /// strings for one search. Written as four `||` checks, the function stops at the
    /// first match and lowercases only the fields it reads.
    private static func has(_ field: String?, _ asking: String) -> Bool {
        guard let field, !field.isEmpty else { return false }
        return field.lowercased().contains(asking)
    }

    /// Every song in the library that matches, up to ``ceiling``, with the album each
    /// song belongs to.
    ///
    /// The album is returned with the song because every screen that draws a hit also
    /// draws its album. Looking the album up again for each row would scan the library
    /// once per row.
    public static func through(_ albums: [CloudAlbum], for asked: String) -> [SongHit] {
        let asking = asked.trimmingCharacters(in: .whitespaces).lowercased()
        guard !asking.isEmpty else { return [] }

        var found: [SongHit] = []

        for album in albums {
            // **Stops early when the search text has changed.** A search walks the whole
            // collection, and the text changes on each keystroke. A walk that cannot stop
            // keeps running after its answer is no longer wanted. Several of those at
            // once would leave the phone without the processor time it needs for the
            // keyboard. The matches found so far are returned, not discarded. The caller
            // discards a cancelled answer anyway, so nothing needs to be decided here.
            if Task.isCancelled { return found }

            // **The album's two fields are checked once per album.** Inside the track loop
            // they would be checked once per track. A twelve-track album would then repeat
            // the same two checks twelve times. Album names and artist names are the fields
            // that most searches match.
            let sleeve = has(album.album, asking) || has(album.artist, asking)

            for track in album.tracks
            where sleeve || has(track.title, asking) || has(track.artist, asking) {
                found.append(SongHit(track: track, album: album))
                if found.count >= ceiling { return found }
            }
        }

        return found
    }

    /// The maximum number of albums one search returns.
    ///
    /// This limit is much lower than the song limit. A library has about ten times
    /// fewer albums than songs. A search that matches more albums than this has
    /// matched an artist name, not one album.
    public static let recordCeiling = 60

    /// Every album in the library whose name or artist matches, up to
    /// ``recordCeiling``.
    ///
    /// **This is a separate question, not the song search with fewer results.** A song
    /// matches through the album it belongs to, so the song search already answers "all
    /// songs by Hex". This function answers "the album Hex", which is a different row
    /// that opens a different screen. A user who types an artist's name sees the artist's
    /// albums above the songs. This lets them find an album without scrolling past forty
    /// tracks.
    ///
    /// Track titles are not checked, on purpose. An album would be listed because one of
    /// its songs matched, even though the album itself has nothing to do with the search.
    /// That row looks like a wrong answer.
    public static func records(_ albums: [CloudAlbum], for asked: String) -> [CloudAlbum] {
        let asking = asked.trimmingCharacters(in: .whitespaces).lowercased()
        guard !asking.isEmpty else { return [] }

        var found: [CloudAlbum] = []

        for album in albums {
            if Task.isCancelled { return found }
            guard has(album.album, asking) || has(album.artist, asking) else { continue }

            found.append(album)
            if found.count >= recordCeiling { return found }
        }

        return found
    }

    /// The album a song belongs to. This is shown on the line under the song's title.
    ///
    /// The album is looked up, not carried in the search result. A list of chosen songs
    /// contains songs. The album a search happened to find a song through is not part of
    /// the choice. A song whose album is not in the library gets a one-track album built
    /// from its own tags.
    public static func albumOf(_ track: CloudTrack, in albums: [CloudAlbum]) -> CloudAlbum {
        albums.first { $0.tracks.contains { $0.rpmId == track.rpmId } }
            ?? CloudAlbum(key: "", album: track.album ?? "", artist: track.artist ?? "",
                          tracks: [track])
    }
}
