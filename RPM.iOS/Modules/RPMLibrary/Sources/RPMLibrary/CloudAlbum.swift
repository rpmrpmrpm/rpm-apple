import Foundation
import RPMKit

/// A record, as the wall draws it: the rows of one album, in the order the record
/// is in.
public struct CloudAlbum: Sendable, Equatable, Identifiable {
    /// The grouping key. Opaque: an identity to compare, not a name to show.
    public let key: String
    public let album: String
    public let artist: String
    public let tracks: [CloudTrack]

    public var id: String { key }

    public init(key: String, album: String, artist: String, tracks: [CloudTrack]) {
        self.key = key; self.album = album; self.artist = artist; self.tracks = tracks
    }

    /// Whether the tracklist is in the order the RECORD is in, rather than
    /// whatever order the server happened to return. False until the library has
    /// been through a catalogue backfill, and the album page says so rather than
    /// presenting an arbitrary order as the running order.
    public var isOrdered: Bool {
        tracks.contains { ($0.tags?.trackNumber ?? 0) > 0 }
    }

    /// How long the record runs, when the catalogue knows. Zero when it does not.
    public var duration: Duration {
        .seconds(tracks.reduce(0.0) { $0 + ($1.tags?.durationSeconds ?? 0) })
    }
}

/// Turning a listing into a wall.
public enum AlbumWall {
    /// Groups rows into records and puts each record in reading order.
    public static func group(_ tracks: [CloudTrack]) -> [CloudAlbum] {
        let byKey = Dictionary(grouping: tracks, by: AlbumGrouping.key(for:))

        let albums = byKey.map { key, rows -> CloudAlbum in
            let folder = AlbumGrouping.folder(of: rows[0].relativePath)

            // Title FIRST, so it is the tiebreak: the disc ordering below keeps
            // ties in the order it was handed, and two tracks with no number of
            // their own then read alphabetically rather than in whatever order the
            // listing arrived in.
            let byTitle = rows.sorted {
                ($0.title ?? "").compare($1.title ?? "", options: .caseInsensitive,
                                         range: nil, locale: .current) == .orderedAscending
            }

            return CloudAlbum(
                key: key,
                album: AlbumGrouping.albumName(for: rows, folder: folder) ?? "",
                artist: AlbumGrouping.albumArtist(for: rows, folder: folder) ?? "",
                tracks: AlbumTracklist.byDisc(byTitle, discOf: AlbumGrouping.disc(of:),
                                              trackOf: AlbumGrouping.track(of:))
                    .flatMap(\.tracks))
        }

        return AlbumSort.by(albums, .artist) {
            AlbumFacts(album: $0.album, artist: $0.artist,
                       addedAt: AlbumSort.addedOf($0.tracks),
                       year: AlbumSort.yearOf($0.tracks))
        }
    }

    /// Whether two readings of the library are the same one.
    ///
    /// What is compared is what is **shown**: the records, their names, and the
    /// name and length of every track on them. Album keys and track counts alone
    /// are not enough: a key is derived from the folder, so a corrected artist
    /// spelling or a fixed running order would not change it, and the wall would
    /// keep drawing the old rows.
    ///
    /// A comparison is used rather than always redrawing: a refresh that finds the
    /// same library must not rebuild a wall of a thousand covers.
    public static func same(_ a: [CloudAlbum], _ b: [CloudAlbum]) -> Bool {
        guard a.count == b.count else { return false }

        for (left, right) in zip(a, b) {
            guard left.key == right.key,
                  left.tracks.count == right.tracks.count,
                  left.album == right.album,
                  left.artist == right.artist
            else { return false }

            for (x, y) in zip(left.tracks, right.tracks) where !same(x, y) { return false }
        }

        return true
    }

    /// What one row is DRAWN as: its identity, what it is called, where it sits on
    /// the record and how long it is, and the work, movement and composer a
    /// classical record's tracklist is drawn from. Not the whole row. A stamp or a
    /// path that changed with nothing on screen changing with it is not worth
    /// redrawing a wall for.
    static func same(_ a: CloudTrack, _ b: CloudTrack) -> Bool {
        a.rpmId == b.rpmId
            && a.title == b.title
            && a.artist == b.artist
            && a.album == b.album
            && (a.tags?.trackNumber ?? 0) == (b.tags?.trackNumber ?? 0)
            && (a.tags?.discNumber ?? 0) == (b.tags?.discNumber ?? 0)
            && abs((a.tags?.durationSeconds ?? 0) - (b.tags?.durationSeconds ?? 0)) < 0.05
            && a.tags?.work == b.tags?.work
            && a.tags?.movementName == b.tags?.movementName
            && a.tags?.composer == b.tags?.composer
    }
}
