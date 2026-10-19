import Foundation
import RPMKit

/// What a store must support for a phone to write a playlist to it.
///
/// This is a protocol so the writing code can be tested with a store that
/// answers or refuses as the test requires. `RPMCloudClient` already conforms.
public protocol PlaylistStore: Sendable {
    func playlists(_ shelf: CloudShelf) async throws -> [CloudPlaylist]

    @discardableResult
    func putPlaylist(_ playlist: CloudPlaylist, ifUnchangedSince: Int64?) async throws -> Int64
}

/// Why a playlist could not be written.
public enum PlaylistWriteError: Error, Sendable, Equatable {
    /// The playlist belongs to another account, so this account may not write it.
    /// The add button is hidden on a borrowed playlist. This error covers any case
    /// that gets past the hidden button.
    case notYours

    /// The playlist was in the listing when the page was drawn, but it is not in
    /// the listing now.
    case gone

    /// **A list the computer cut, not a list somebody made.** Its id names nothing
    /// in the store. A write would not change a list. It would create a playlist
    /// from the cut, and the computer replaces that cut on its next run. The add
    /// button and the drag handles are hidden on these lists. This error covers any
    /// case that gets past them.
    case notYoursToCut

    /// Two refusals in a row. Another device is writing to the same playlist in a
    /// loop. Failing is better than letting the phone keep retrying against someone
    /// else's edit.
    case beingChangedElsewhere

    /// **This error prevents deleting music.** A playlist can name tracks that this
    /// phone cannot see. If the whole running order were written, those tracks
    /// could not be named in the write, and the playlist would lose one song each
    /// time the user dragged a row.
    case wouldDropUnseenTracks(Int)

    public var userMessage: String {
        switch self {
        case .notYours:
            return Loc.get("Rpm_PlaylistWrite_NotYours")
        case .gone:
            return Loc.get("Rpm_PlaylistWrite_Gone")
        case .notYoursToCut:
            return Loc.get("Rpm_PlaylistWrite_Generated")
        case .beingChangedElsewhere:
            return Loc.get("Rpm_PlaylistWrite_Busy")
        case .wouldDropUnseenTracks:
            return Loc.get("Rpm_PlaylistWrite_Unseen")
        }
    }
}

/// Makes a playlist, adds songs to one, and changes the order of one.
///
/// **The phone never owns a playlist that it did not make.** The computer writes
/// its copy of each playlist to the cloud from its own tree on every sync run. A
/// change made on the phone stays only until that computer next runs, unless the
/// computer is updated to take the change in. A playlist made on the phone has no
/// owner yet, so it is not affected.
///
/// Every write names the copy it replaces. When a write is refused, the two
/// versions are merged, not retried blindly. The phone always has a common base:
/// the copy this call read a moment earlier. Keeping it costs nothing. This is what
/// turns "their change or mine" into "both".
public struct PlaylistWriter: Sendable {
    private let store: any PlaylistStore

    /// Returns the shelf a track belongs to. **This is required, not a convenience.**
    /// A playlist names tracks by id under one account. An id from another account's
    /// collection resolves to nothing here. Every device that reads the playlist
    /// afterwards would count those tracks as missing.
    private let shelfOf: @Sendable (String) -> CloudShelf

    /// Creates new playlist ids. A test can supply its own. A new id is what makes
    /// a write create a playlist. An id the store already holds would replace a
    /// playlist instead.
    private let mint: @Sendable () -> String

    public init(store: any PlaylistStore,
                shelfOf: @escaping @Sendable (String) -> CloudShelf,
                mint: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.store = store
        self.shelfOf = shelfOf
        self.mint = mint
    }

    // ── making one ──

    /// Makes a playlist and puts it in the cloud.
    ///
    /// - Parameters:
    ///   - name: The name to use. It is trimmed here, because a trailing space makes
    ///     the name look like a different playlist.
    ///   - folder: The folder to file it in, outermost first. An empty array means
    ///     the top of the tree, and it is a real answer. The argument has no default,
    ///     so every caller decides the folder.
    ///   - tracks: The songs to put in, in the order they should appear.
    public func create(
        name: String, folder: [String], tracks: [CloudTrack]
    ) async throws -> PlaylistSet {
        let id = mint()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let own = tracks.filter { shelfOf($0.rpmId).isOwn }

        // The precondition is `0`, not `nil`. The id was made a moment ago, so nothing
        // should be stored under it. If the store reports that it is already in use,
        // the write fails. Overwriting an existing playlist would be wrong.
        let stamp = try await store.putPlaylist(
            CloudPlaylist(playlistId: id, name: trimmed, trackIds: own.map(\.rpmId),
                          folder: folder, updatedAt: 0),
            ifUnchangedSince: 0)

        // The result is built from what was sent, not read back from the store. The row
        // was written a moment ago, and a second request would make the user wait with
        // the sheet still open. `missing` is 0 by construction, because every track
        // came from the listing.
        return PlaylistSet(id: id, name: trimmed, tracks: own, missing: 0,
                           folder: folder, stamp: stamp, shelf: .own, origin: .stored)
    }

    // ── adding to one ──

    /// What to do with a song that the playlist already contains.
    ///
    /// There is no default, because both answers are valid, and only the caller knows
    /// which one the user wants. A playlist can contain the same song twice on
    /// purpose. A plain "add to playlist" action does not usually mean adding a
    /// second copy. So if the caller does not say, nothing is added. Adding a second
    /// copy is an explicit choice, and this value is the only way to make it.
    public enum AlreadyThere: Sendable, Equatable {
        /// Keep the copy already in the list. The song is not added, and it is not
        /// included in the result.
        case leaveIt

        /// Add another copy at the end of the list, because the caller asked for it.
        case addAnother
    }

    /// Adds songs to a playlist that already exists.
    ///
    /// - Parameter whenAlreadyThere: What to do with a song that the list already
    ///   contains. **There is no default.** Adding a second copy without the user
    ///   asking, and quietly adding nothing, are both wrong. The caller must choose.
    ///   See ``AlreadyThere``.
    ///
    /// - Returns: The songs that were actually added, in the order they were added.
    ///   An empty array is a valid answer. It means every song was already in the
    ///   playlist, and the caller chose `.leaveIt`.
    @discardableResult
    public func add(to playlist: PlaylistSet, tracks: [CloudTrack],
                    whenAlreadyThere: AlreadyThere) async throws -> [CloudTrack] {
        guard playlist.shelf.isOwn else { throw PlaylistWriteError.notYours }
        guard playlist.origin == .stored else { throw PlaylistWriteError.notYoursToCut }

        // The listing is read again, and the write does not use the copy the page holds.
        // A page can stay open for a long time, and the order it shows may be several
        // changes out of date.
        let stored = try await store.playlists(.own)
        guard let current = stored.first(where: { $0.playlistId == playlist.id })
        else { throw PlaylistWriteError.gone }

        var ids = current.trackIds
        var have = Set(ids)
        var added: [CloudTrack] = []

        for track in tracks {
            guard shelfOf(track.rpmId).isOwn else { continue }

            // `insert` runs for every song, so the set stays correct for the songs that
            // follow. The result only decides whether this one song is added.
            let isNew = have.insert(track.rpmId).inserted
            guard isNew || whenAlreadyThere == .addAnother else { continue }

            ids.append(track.rpmId)
            added.append(track)
        }

        guard !added.isEmpty else { return [] }

        _ = try await writeAgainst(
            CloudPlaylist(playlistId: current.playlistId, name: current.name,
                          trackIds: ids, folder: current.folderChain, updatedAt: 0),
            ancestor: current.trackIds, stamp: current.updatedAt)

        return added
    }

    // ── changing the order ──

    /// Writes a playlist's running order back to the cloud. The computer that keeps
    /// the music picks it up on its next sync.
    ///
    /// The whole playlist is sent every time, because that is the only form the
    /// store accepts. For this reason the caller must pass **every** track in the
    /// playlist, not only the tracks this phone can see.
    @discardableResult
    public func reorder(_ set: PlaylistSet, tracks: [CloudTrack]) async throws -> Int64 {
        guard set.shelf.isOwn else { throw PlaylistWriteError.notYours }
        guard set.origin == .stored else { throw PlaylistWriteError.notYoursToCut }
        guard set.missing == 0 else {
            throw PlaylistWriteError.wouldDropUnseenTracks(set.missing)
        }

        return try await writeAgainst(
            CloudPlaylist(playlistId: set.id, name: set.name, trackIds: tracks.map(\.rpmId),
                          folder: set.folder, updatedAt: 0),
            ancestor: set.tracks.map(\.rpmId), stamp: set.stamp)
    }

    // ── the conditional write ──

    /// Writes a playlist and names the copy it replaces. If another device changed
    /// the playlist first, the two versions are merged and the write is retried once.
    ///
    /// **The name and the folder always come from the store.** A phone cannot change
    /// either one. So any difference in them comes from a rename on a computer, and
    /// this code leaves it alone.
    ///
    /// The retry happens once. If the second write is also refused, another device is
    /// writing in a loop, and this throws `beingChangedElsewhere`.
    @discardableResult
    private func writeAgainst(
        _ wanted: CloudPlaylist, ancestor: [String], stamp: Int64
    ) async throws -> Int64 {
        var wanted = wanted, ancestor = ancestor, stamp = stamp

        for _ in 0..<2 {
            do {
                // `nil` means no precondition. A row written before the store sent
                // stamps has a stamp of 0. A precondition built from that value would
                // refuse every write to the row, so `nil` is used instead.
                return try await store.putPlaylist(
                    wanted, ifUnchangedSince: stamp > 0 ? stamp : nil)
            } catch let clash as PlaylistConflict {
                guard let stored = clash.stored else {
                    // The store refused without saying what it holds. There is nothing to
                    // merge against. Retrying without a base would overwrite the other
                    // device's change, so the write fails instead.
                    throw PlaylistWriteError.beingChangedElsewhere
                }

                let merged = PlaylistMerge.songs(ancestor: .published(ancestor),
                                                 mine: wanted.trackIds,
                                                 theirs: stored.trackIds)

                wanted = CloudPlaylist(playlistId: stored.playlistId, name: stored.name,
                                       trackIds: merged, folder: stored.folderChain,
                                       updatedAt: 0)
                ancestor = stored.trackIds
                stamp = stored.updatedAt
            }
        }

        throw PlaylistWriteError.beingChangedElsewhere
    }
}
