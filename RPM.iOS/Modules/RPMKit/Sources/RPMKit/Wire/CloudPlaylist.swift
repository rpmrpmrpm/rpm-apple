import Foundation

/// A playlist as the cloud holds it: a name and the tracks it plays, in order.
///
/// Flat on purpose. A playlist that nests other playlists is resolved to its
/// play order before it goes up, so anything reading one gets a list it can play
/// rather than a graph it has to walk and guard against cycles. The cost is that
/// editing a nested playlist leaves its parents stale until they are pushed
/// again.
public struct CloudPlaylist: Codable, Hashable, Sendable, Identifiable {
    public let playlistId: String
    public let name: String
    public let trackIds: [String]

    /// The folders this playlist sits in, outermost first. Segments rather than
    /// one path string, because a folder may be called anything a person can
    /// type, including something with a slash in it, and a separator that can
    /// appear inside a name is a separator that cannot be undone.
    public let folder: [String]?

    /// The store's own stamp. What `putPlaylist` sends back as
    /// `ifUnchangedSince`, which is the whole of what makes two phones editing
    /// one list safe.
    public let updatedAt: Int64

    public var id: String { playlistId }

    /// Read the folders through this, never through `folder`: the field is
    /// absent on playlists that were written without folders, and "no field"
    /// and "top of the tree" are the same answer.
    public var folderChain: [String] { folder ?? [] }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playlistId = try c.decode(String.self, forKey: .playlistId)
        name       = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        trackIds   = try c.decodeIfPresent([String].self, forKey: .trackIds) ?? []
        folder     = try c.decodeIfPresent([String].self, forKey: .folder)
        updatedAt  = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }

    public init(playlistId: String, name: String, trackIds: [String],
                folder: [String]? = nil, updatedAt: Int64 = 0) {
        self.playlistId = playlistId; self.name = name; self.trackIds = trackIds
        self.folder = folder; self.updatedAt = updatedAt
    }
}

/// The listing envelope.
///
/// `owner` is here for the same reason it is on `CloudListPage`: the playlists
/// of another account have to be checked to belong to that account before a
/// single one is kept.
public struct CloudPlaylistsResponse: Codable, Sendable {
    public let playlists: [CloudPlaylist]
    public let owner: String?
}
