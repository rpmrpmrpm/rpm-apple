import Foundation
import CryptoKit

/// WHICH picture of a record is being asked for.
///
/// **A parameter with no default, and that is the whole point of the type.** The two
/// pictures live in one prefix in the store and are told apart only by their
/// key, so a caller that forgot to say which one it meant would ask for the cover and
/// get it, silently and with the wrong picture. Naming it at every call site
/// makes the compiler enforce this.
///
/// It decides more than the key on this side: a disc label is a transparent PNG that
/// must not be re-encoded as a JPEG, is never in a file's tags, and has no colour
/// worth reading off it. See ``RecordPicture/keepsAlpha`` and `ArtworkStore`.
public enum RecordPicture: String, Sendable, CaseIterable {
    /// The album's cover, as the library displays it.
    case cover

    /// The record itself: the transparent picture of the disc that the turntable
    /// shows in place of the one it draws.
    case disc

    /// What goes in front of the two names in the hash. The desktop's
    /// `AlbumArt.DiscKeyFor` writes `disc|artist|album`, and the cover's key has
    /// no prefix, so the empty string here is a fixed part of the contract and
    /// not a tidy default.
    var stamp: String {
        switch self {
        case .cover: return ""
        case .disc: return "disc|"
        }
    }

    /// Whether the picture's transparency must be kept.
    ///
    /// A disc label IS a disc: cut round out of a photograph, with the corners of the
    /// photograph made transparent. Stored as a JPEG it comes back as a square, and
    /// the turntable would show a rectangle turning on the deck.
    public var keepsAlpha: Bool { self == .disc }
}

/// The key under which an album's cover is stored.
///
/// **Derived, never assigned.** The computer that uploads a cover and the phone
/// that asks for it compute the same string without being told it. That is the
/// only reason a cover added to a record on a desktop is found for that record on
/// a phone. So the normalisation is part of the contract and not a detail:
/// trimmed, lower-cased, and the same on both sides. Changing any of it orphans
/// every cover already stored.
public enum AlbumArtKey {
    /// The key for an album artist and a title.
    ///
    /// A hash, so it is safe as a path component whatever the record is called:
    /// slashes, colons, emoji and right-to-left titles included.
    public static func of(_ picture: RecordPicture,
                          albumArtist: String?, album: String?) -> String {
        digest("\(picture.stamp)\(normalize(albumArtist))|\(normalize(album))")
    }

    /// The key for a track's album.
    ///
    /// **The fallback is here and not at the call sites, and it is not `??`.**
    /// A tag that is present but blank is not an album artist: a caller writing
    /// `albumArtist ?? artist` uses the empty string as the key, and one that
    /// trims first uses the artist. Two keys for one album mean the
    /// cover is stored where nothing will look for it.
    public static func forTrack(_ picture: RecordPicture,
                                albumArtist: String?, artist: String?, album: String?) -> String {
        of(picture, albumArtist: isBlank(albumArtist) ? artist : albumArtist, album: album)
    }

    /// Both forms of one album's key, best first.
    ///
    /// The key was made from the file's own tags when the cover was uploaded.
    /// The catalogue a phone reads may have no album artist, for rows written
    /// before the catalogue had that field, and then the album artist and the track
    /// artist give two different keys for one record. Asking with both costs two
    /// dictionary lookups and decides between a cover and a placeholder.
    public static func spellings(_ picture: RecordPicture,
                                 albumArtist: String?, artist: String?, album: String?) -> [String] {
        let byAlbumArtist = forTrack(picture, albumArtist: albumArtist, artist: artist, album: album)
        let byArtist = of(picture, albumArtist: artist, album: album)
        return byAlbumArtist == byArtist ? [byAlbumArtist] : [byAlbumArtist, byArtist]
    }

    /// Every key one track's album could be stored under.
    public static func spellings(_ picture: RecordPicture, for track: CloudTrack) -> [String] {
        spellings(picture, albumArtist: track.tags?.albumArtist,
                  artist: track.artist, album: track.album)
    }

    /// Every key a whole record could be stored under, in the order they were found.
    ///
    /// It reads all the tracks and not only the first, because the tags of a
    /// record are not always the same on every track: a set ripped in two
    /// sessions can have the album artist on half its files. The desktop uploads a
    /// cover under the tags of whichever track it was holding, so an album
    /// can be stored under a form that only its ninth track knows.
    public static func spellings(_ picture: RecordPicture, for tracks: [CloudTrack]) -> [String] {
        var seen = Set<String>()
        var all: [String] = []

        for track in tracks {
            for key in spellings(picture, for: track) where seen.insert(key).inserted {
                all.append(key)
            }
        }
        return all
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Thirty-two hex characters: the first sixteen bytes of the digest, which is
    /// what the store checks a key against and what the desktop writes.
    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
