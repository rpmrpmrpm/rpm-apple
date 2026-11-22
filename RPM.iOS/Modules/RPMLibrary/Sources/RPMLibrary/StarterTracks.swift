import Foundation
import RPMKit

/// The three records that ship inside the iPhone app, the desktop's starter tracks (`StarterMusic`
/// there): Connect by Northern Palaces, Satie's first Gymnopédie, and the first movement of the
/// Moonlight Sonata played by Paul Pitman for Musopen. A person whose own collection holds no
/// music sees them in its place (``shown(_:starters:reached:force:)``), so a new account has
/// something to play, and the welcome has a song to spin. The Android phone ships the same three.
///
/// **The cloud never sees them.** They are not in the cloud's catalogue, so every write that names
/// a track or a record would fail, or store an id that nobody can resolve. Their ids all start with
/// ``prefix``, and each write that could reach them asks ``isStarter(_:)`` first: the
/// favourite marks, the playlists, the downloads, Quick selection, the play counts and the listens
/// sent to the store, the lyric timing and the chosen sheet, the credits, and the counts and badges
/// a profile shows. The menus leave those items out.
///
/// They are laid in where the own shelf is put on the wall (`LibrarySession`), so the copy of the
/// library on disk and the cloud never hold them. The files are in the iPhone's `RPMUI` package
/// (`StarterFiles`). The Apple TV app does not ship them and never shows them: only the iPhone
/// hands them to the session.
public enum StarterTracks {
    /// The start of every starter track's id. A cloud id is a GUID, so it never starts so.
    public static let prefix = "rpm-starter-"

    /// The folder every starter track's path is in. The wall groups a record by its folder
    /// (``AlbumGrouping/key(for:)``), so every starter record's key starts with `folder:` and this.
    private static let folder = "rpm-starter/"

    /// The bit rate of the shipped files, in kilobits a second.
    public static let kilobits = 128

    /// One record: the name its files and its id are made from, whether it ships a disc picture,
    /// and its one track.
    public struct Record: Sendable {
        public let name: String
        public let hasDisc: Bool
        public let track: CloudTrack
    }

    /// The three records. The tags are the desktop files' own. The loudness and the true peak were
    /// measured on the shipped AAC files with ffmpeg's ebur128 filter. The peak is linear, where
    /// 1.0 is full scale, as the levelling reads it (``Level``).
    public static let records: [Record] = [
        record("connect", title: "Connect (2017 Version)", artist: "Northern Palaces",
               album: "Connect - Single", year: 2017, genre: "Electronic / Dance",
               seconds: 246.676, lufs: -11.3, truePeak: 1.202, releaseType: "Single"),
        record("gymnopedie", title: "Gymnopedie no. 1 - lent et douloureux", artist: "Erik Satie",
               album: "Gymnopedie no. 1", year: 1998, genre: "Classical",
               seconds: 183.595, lufs: -25.9, truePeak: 0.457, composer: "Erik Satie",
               releaseType: "Single"),
        record("moonlight",
               title: "Sonata No.14 in C-sharp minor, Op.27, No.2 (\"Moonlight\"): I. Adagio sostenuto",
               artist: "Ludwig van Beethoven", album: "Moonlight Sonata", year: 1801,
               genre: "Classical", seconds: 335.776, lufs: -32.4, truePeak: 0.209,
               composer: "Ludwig van Beethoven", hasDisc: true),
    ]

    /// The three tracks.
    public static let tracks: [CloudTrack] = records.map(\.track)

    /// The three records as the wall draws them, one track each.
    public static let albums: [CloudAlbum] = AlbumWall.group(tracks)

    /// The welcome's song, in the order it is chosen: Connect first, because it has a beat to show
    /// the player off with, then the Gymnopédie. The Moonlight Sonata is long and quiet, so it comes
    /// last. See ``WelcomeSong``.
    public static let welcomeOrder: [String] = ["connect", "gymnopedie", "moonlight"].map { prefix + $0 }

    /// Whether `rpmId` is a starter track.
    public static func isStarter(_ rpmId: String) -> Bool { rpmId.hasPrefix(prefix) }

    /// Whether `album` is a starter record: it has tracks, and every one is a starter track.
    public static func isStarter(_ album: CloudAlbum) -> Bool {
        !album.tracks.isEmpty && album.tracks.allSatisfy { isStarter($0.rpmId) }
    }

    /// Whether `albumKey` is a starter record's key (``AlbumGrouping/key(for:)`` of a starter track).
    public static func isStarterKey(_ albumKey: String) -> Bool {
        albumKey.hasPrefix("folder:" + folder)
    }

    /// Whether `albums` is the starter shelf, shown in place of an empty collection, rather than
    /// the person's music. An empty wall is not the starter shelf.
    public static func isStarterShelf(_ albums: [CloudAlbum]) -> Bool {
        !albums.isEmpty && albums.allSatisfy { isStarter($0) }
    }

    /// The record of the starter track `rpmId`, or nil for any other track.
    public static func record(of rpmId: String) -> Record? {
        guard isStarter(rpmId) else { return nil }
        return records.first { $0.track.rpmId == rpmId }
    }

    /// The record `album` is, when it is a starter record, or nil.
    public static func record(of album: CloudAlbum) -> Record? {
        guard isStarter(album), let first = album.tracks.first else { return nil }
        return record(of: first.rpmId)
    }

    /// The own shelf as it is shown: `albums` as read, or `starters` in their place when the store
    /// answered (`reached`) and the collection holds no tracks.
    ///
    /// - Parameters:
    ///   - starters: what the app ships. Empty on the Apple TV, which then always shows `albums`.
    ///   - reached: whether the store has answered for the own shelf. A read that failed gives no
    ///     records too, and that is not an empty collection: the wall says it could not be read.
    ///   - force: shows `starters` over a collection that has music, to look at a new account's
    ///     screens. Only a debug build asks for it.
    public static func shown(_ albums: [CloudAlbum], starters: [CloudAlbum], reached: Bool,
                             force: Bool = false) -> [CloudAlbum] {
        guard !starters.isEmpty else { return albums }
        if force { return starters }
        let empty = albums.allSatisfy { $0.tracks.isEmpty }
        return empty && reached ? starters : albums
    }

    // ── the rows ──

    private static func record(_ name: String, title: String, artist: String, album: String,
                               year: Int, genre: String, seconds: Double, lufs: Double,
                               truePeak: Double, composer: String? = nil,
                               releaseType: String? = nil, hasDisc: Bool = false) -> Record {
        var tags = CloudTrackTags()
        tags.durationSeconds = seconds
        tags.trackNumber = 1
        tags.discNumber = 1
        tags.year = year
        tags.genre = genre
        tags.albumArtist = artist
        tags.extension = "m4a"
        tags.channels = 2
        tags.sampleRate = 44_100
        tags.bitrateKbps = kilobits
        tags.codecDescription = "AAC"
        tags.composer = composer
        tags.loudnessLufs = lufs
        tags.truePeak = truePeak
        tags.releaseType = releaseType

        let track = CloudTrack(rpmId: prefix + name, relativePath: folder + name + "/" + name + ".m4a",
                               title: title, artist: artist, album: album, tags: tags)
        return Record(name: name, hasDisc: hasDisc, track: track)
    }
}
