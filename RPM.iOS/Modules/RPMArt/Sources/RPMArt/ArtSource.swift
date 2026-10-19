import Foundation
import RPMKit

/// Where the pictures come from.
///
/// A protocol so the store can be tested without a network, and so the store
/// depends on a few questions rather than on the whole cloud client. `RPMCloudClient`
/// answers all of them; the conformance below is the entire adapter.
public protocol ArtSource: Sendable {
    /// Which records on this shelf have a stored cover, and which version.
    ///
    /// Throws when the store could not be reached. That is a different answer
    /// from a collection that has no covers in it.
    func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover]

    /// Where one record's cover can be fetched from, signed, as the original or as one
    /// of the API's cut copies. Nil when there is none, which is the ordinary answer.
    func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover?

    /// The picture, from the signed address, carrying no credential.
    func artwork(at url: URL) async throws -> Data

    /// Pictures of the artist (not of the record), best first, for the screen that shows one
    /// behind the record.
    ///
    /// Empty is the ordinary answer and not an error: most artists in most libraries have
    /// no photograph anywhere. **Throwing is the other answer**, and the two must not be
    /// confused. "Nobody has a picture of them" is worth remembering for the session.
    /// "The store could not be asked" (for example the phone has not finished signing in)
    /// must not be remembered, or the artist stays blank for an hour.
    func artistPictures(artist: String, album: String?) async throws -> ArtistPictures

    /// A track's sidecar, which holds the art embedded in the user's own file.
    func sidecar(rpmId: String) async throws -> TagSidecar?

    /// Where one playlist's own picture can be fetched from, signed. Nil when the
    /// store has none, which is the ordinary answer for a list on the automatic cover.
    func playlistArt(_ shelf: CloudShelf, playlistId: String) async -> URL?
}

extension ArtSource {
    /// Nil, for a source that has no pictures of playlists, such as a stand-in in a test.
    public func playlistArt(_ shelf: CloudShelf, playlistId: String) async -> URL? { nil }
}

extension RPMCloudClient: ArtSource {}
