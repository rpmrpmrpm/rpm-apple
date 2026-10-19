import Foundation
import RPMKit

/// The cloud client, as a source of listings.
///
/// The whole adapter, and it exists because `LibrarySource` asks one question and
/// the client's own `list` takes a progress callback as well. A protocol with an
/// optional second parameter in it would make every test double carry a parameter
/// no test uses.
extension RPMCloudClient: LibrarySource {
    public func list(_ shelf: CloudShelf) async throws -> [CloudTrack] {
        try await list(shelf, onProgress: nil)
    }
}

/// The cloud client is also a playlist store. It already speaks both halves of the
/// protocol; this only says so.
extension RPMCloudClient: PlaylistStore {}
