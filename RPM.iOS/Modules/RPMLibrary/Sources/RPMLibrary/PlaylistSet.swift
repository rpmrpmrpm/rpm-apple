import Foundation
import RPMKit

/// Who made a running order. This decides whether the list may be changed.
///
/// **This is a type, not a flag on the view that draws the list.** A generated list
/// is a list of ids under an id that nothing in the cloud stores. Writing to it
/// would not edit anything. It would create a new playlist from the cut, and the
/// computer replaces that cut on its next run. A `PlaylistSet` looks the same
/// either way: same name, same tracks, same shelf. So the origin is stated on every
/// set, and the compiler makes each call site decide what to do with it.
public enum PlaylistOrigin: Sendable, Equatable {
    /// A playlist somebody made. It is stored in the cloud under an id that exists.
    case stored

    /// A list the computer cut from the collection. Examples are a mood, a mood
    /// within a genre, or a decade. It is read and played here, and never written.
    case generated
}

/// A playlist as the phone plays it: the cloud's running order, resolved to the
/// tracks it names.
public struct PlaylistSet: Sendable, Equatable, Identifiable {
    /// The cloud id. It is the same as the id of the desktop's copy, so the same
    /// playlist is the same row between launches.
    public let id: String

    public let name: String
    public let tracks: [CloudTrack]

    /// The number of its tracks that are not in this library.
    ///
    /// A cloud playlist names tracks by id. The desktop sends the order before the
    /// audio has finished uploading, so **a playlist can be ahead of the store it
    /// plays from**. The missing count is shown rather than treated as an error, so
    /// the reader can see "eleven of twelve" and does not get a playlist that is
    /// silently short.
    public let missing: Int

    /// The folders this playlist sits in on the computer that keeps it, outermost
    /// first. An empty array means the top of the tree. The phone shows only the
    /// last name, because a heading names a place and not a path. The whole chain is
    /// still carried, so that a playlist made here returns to the right folder when
    /// a computer receives it.
    public let folder: [String]

    /// The store's stamp for the copy this set was read from. A write sends the
    /// stamp of the copy it replaces, so the store can refuse a write made against a
    /// copy that has since changed. Zero means the store did not send a stamp. It
    /// means "cannot tell", and the write goes ahead regardless.
    public let stamp: Int64

    /// Whose playlist this is.
    ///
    /// This is stored on the set rather than worked out from the tracks. An EMPTY
    /// borrowed playlist has no tracks to work it out from, and the answer decides
    /// whether the page that opens it shows the add button and the drag handles.
    public let shelf: CloudShelf

    /// Whether a person or the computer made this list. **There is no default**,
    /// because the two look identical on the phone and only one of them may be
    /// written to.
    public let origin: PlaylistOrigin

    /// The key that the computer used to make a generated list: the mood, the
    /// genre and the decade. This is nil for a playlist somebody made. Those are
    /// keyed on nothing and drawn from their picture.
    ///
    /// **The key is stored, not read back from the id.** The id is an opaque string
    /// from the store, and the key is the source of the list's frame colours. A
    /// parser that split the id again would be a second reading of the same
    /// information. See ``GeneratedCut`` and `GeneratedListLook`.
    public let cut: GeneratedCut?

    /// Whether the phone may write this running order back. The list must be on the
    /// user's own shelf, and it must be a list somebody made. Everything else is
    /// read and played only.
    public var isWritable: Bool { shelf.isOwn && origin == .stored }

    /// The picture to ask for, given the list's id, shelf and cut.
    ///
    /// A playlist's cover is either chosen by the user or cut by the app. It is drawn
    /// on the computer that keeps the playlist. The id is the store's id, not this
    /// app's. A generated list uses a mark that no cloud id carries. See
    /// ``GeneratedLists/storeId(of:)``.
    ///
    /// **Every screen that draws a list uses this one property.** The playlists tab,
    /// the home screen's rows and its banner all ask here. A second way of computing
    /// the picture would give one list two different pictures.
    public var picture: ListPicture {
        ListPicture(id: GeneratedLists.storeId(of: self), shelf: shelf, cut: cut)
    }

    /// - Parameter cut: The key for a generated list. The parameter has a default,
    ///   and it appears only here. Every other field describes any list. This one
    ///   describes only generated lists, and the many call sites that build a stored
    ///   playlist have no value to pass for it.
    public init(id: String, name: String, tracks: [CloudTrack], missing: Int,
                folder: [String], stamp: Int64, shelf: CloudShelf, origin: PlaylistOrigin,
                cut: GeneratedCut? = nil) {
        self.id = id; self.name = name; self.tracks = tracks; self.missing = missing
        self.folder = folder; self.stamp = stamp; self.shelf = shelf; self.origin = origin
        self.cut = cut
    }

    /// The number of copies of a song this list already holds.
    ///
    /// This returns a count, not a yes or no. The caller asks whether to add another
    /// copy, and "already in it twice" is a different answer from "already in it".
    ///
    /// The count uses only the tracks this library could resolve. A song that this
    /// phone has never seen gives a count of zero. That is the correct answer for
    /// what this phone can show. Every write asks the store again.
    public func copies(of track: CloudTrack) -> Int {
        tracks.reduce(0) { $0 + ($1.rpmId == track.rpmId ? 1 : 0) }
    }

    public var duration: Duration {
        .seconds(tracks.reduce(0.0) { $0 + ($1.tags?.durationSeconds ?? 0) })
    }

    /// Resolves the cloud's running orders against a track listing.
    ///
    /// This is a pure function of its two inputs. A screen can check how a set of
    /// playlists looks against a library without fetching either one again.
    ///
    /// - Parameter shelf: Whose playlists these are, and whose listing their ids are
    ///   resolved against. **These two must match.** A borrowed shelf's running orders
    ///   name that owner's tracks. Looking them up in the reader's own library would
    ///   report every one of them as missing.
    public static func resolve(
        _ playlists: [CloudPlaylist], against tracks: [CloudTrack], shelf: CloudShelf
    ) -> [PlaylistSet] {
        guard !playlists.isEmpty else { return [] }

        // If an id appears twice in the listing, the last one is used. This is not
        // treated as an error, because a duplicate id should not stop the user from
        // seeing their playlists.
        var byId: [String: CloudTrack] = [:]
        byId.reserveCapacity(tracks.count)
        for track in tracks { byId[track.rpmId] = track }

        return playlists.map { playlist in
            let found = playlist.trackIds.compactMap { byId[$0] }

            return PlaylistSet(
                id: playlist.playlistId,
                name: playlist.name,
                tracks: found,
                missing: playlist.trackIds.count - found.count,
                folder: playlist.folderChain,
                stamp: playlist.updatedAt,
                shelf: shelf,
                origin: .stored)
        }
        .sorted {
            $0.name.compare($1.name, options: .caseInsensitive,
                            range: nil, locale: .current) == .orderedAscending
        }
    }
}

/// The inputs that choose a list's picture.
///
/// **The cut is part of the value because it decides where the picture comes from.**
/// A generated list that has a photograph in `scripts/playlist-photos.json` uses
/// that photograph, which ships inside the app. Every other list uses the picture
/// the store holds. A caller that had only the id and the shelf could not tell these
/// apart, and would show the store's picture for a list that has its own photograph.
/// The initializer is internal, so ``PlaylistSet/picture`` is the only way to make
/// a value of this type.
public struct ListPicture: Hashable, Sendable {
    /// The id the store uses for the picture. See ``GeneratedLists/storeId(of:)``.
    public let id: String

    /// Whose list this is. The lists on a borrowed shelf use their owner's pictures.
    public let shelf: CloudShelf

    /// The key of a generated list, or nil for a list somebody made.
    public let cut: GeneratedCut?

    init(id: String, shelf: CloudShelf, cut: GeneratedCut?) {
        self.id = id; self.shelf = shelf; self.cut = cut
    }
}

/// The key the computer used to make a generated list: the mood, the genre it is
/// narrowed to, and the decade.
///
/// **These three fields and nothing derived from them.** Both apps roll the colours
/// of a list's frame from exactly these three values. So the key is what is passed
/// on, not a computed result. See `GeneratedListLook`, where the colours are rolled,
/// and `CloudMoodList`, where these values arrive.
public struct GeneratedCut: Sendable, Equatable, Hashable {
    /// The mood, spelled as the desktop's `SmartPlaylistKind` spells it.
    public let kind: String

    /// The genre the list is narrowed to, or nil for the whole collection.
    public let genre: String?

    /// The first year of the decade the list is narrowed to, or 0 for all decades.
    public let decade: Int

    public init(kind: String, genre: String?, decade: Int) {
        self.kind = kind; self.genre = genre; self.decade = decade
    }
}
