import Foundation

/// The store's copy of a playlist is not the one being replaced.
///
/// **Nothing was written**, and this carries what is there instead. That copy is
/// the whole reason a write is made conditionally: a merge needs the other side,
/// not a sentence about it.
///
/// `stored` is nil only where the store refused without saying what it holds, which
/// is a store that does not answer with the copy. A caller that gets nil has to read
/// the playlist again before it can merge.
public struct PlaylistConflict: Error, Sendable {
    public let stored: CloudPlaylist?

    /// The name as the writer had it.
    public let name: String

    public init(stored: CloudPlaylist?, name: String) {
        self.stored = stored
        self.name = name
    }
}
