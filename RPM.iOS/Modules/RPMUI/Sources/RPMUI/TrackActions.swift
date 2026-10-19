import SwiftUI
import RPMKit

/// The actions available on a song wherever it is listed: play it next, mark it as a
/// favourite, and add it to a playlist.
///
/// **Swipe actions and a context menu are both provided.** `swipeActions` works where
/// the row is in a `List`. The context menu works everywhere, including on a row that is
/// not in a list. (The Uno app draws a drawer under the row instead, because Uno has
/// neither of these.)
///
/// **Swipe the row right to play the song after the current one**, and swipe left for
/// the other two actions. This matches the Uno app and the desktop drawer. The queue
/// list uses the same direction: see ``QueueOverlay``, where a leading swipe moves a
/// row up to play next.
///
/// **Play next is offered on every row; the other two actions are not.** A favourite
/// mark is stored against an id, and a playlist names songs by id. A song from a shelf
/// borrowed from another account is not owned by this account, so `PlaylistWriter.add`
/// silently drops it. Showing the buttons would make them light up, send a request and
/// then quietly revert. Playing still works on a borrowed shelf, because its songs
/// stream from the owner's store.
///
/// Two other checks enforce the same rule, and all three are wanted: the playlist
/// picker lists only this account's own playlists, and `PlaylistWriter` answers
/// ``PlaylistWriteError/notYours`` to anything else. This view is the check the user
/// actually sees.
public struct TrackActions: ViewModifier {
    private let track: CloudTrack
    private let marked: Bool

    /// Whether this song is on this account's own shelf. **There is no default**: it
    /// decides whether favourite and playlist actions can work at all, and a caller that
    /// forgets to set it is the mistake this type exists to prevent.
    private let mine: Bool

    /// What "play next" means for this row. **It differs between an ordinary song list
    /// and the queue itself.**
    ///
    /// A row in the library, on an album or in a stored playlist is not in the queue, so
    /// "play next" adds it to the queue. A row in the queue is already queued. Adding it
    /// again would create a second copy, but the user means *move this song up*. The
    /// queue handles that itself with its own actions: see ``QueueOverlay``, whose
    /// leading swipe moves the row to play next.
    ///
    /// Each caller states which case it is, instead of the type working it out from a flag.
    public enum UpNext {
        /// Put the song in the queue after the album that is playing.
        case send((CloudTrack) -> Void)

        /// No action: this row is already in the queue.
        case itIsTheQueue
    }

    private let upNext: UpNext
    private let onMark: (CloudTrack, Bool) -> Void
    private let onFile: (CloudTrack) -> Void

    public init(track: CloudTrack, marked: Bool, mine: Bool, upNext: UpNext,
                onMark: @escaping (CloudTrack, Bool) -> Void,
                onFile: @escaping (CloudTrack) -> Void) {
        self.track = track
        self.marked = marked
        self.mine = mine
        self.upNext = upNext
        self.onMark = onMark
        self.onFile = onFile
    }

    /// The closure that queues the song, or `nil` on a row that is already in the queue.
    private var sender: ((CloudTrack) -> Void)? {
        guard case .send(let put) = upNext else { return nil }
        return put
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        let row = content
            .contextMenu {
                playNext

                // A borrowed row gets only the action that works on it. The other
                // actions are left out, not disabled: a disabled button suggests "not
                // now", but they never work from here.
                if mine {
                    Button { mark() } label: {
                        Label(favourite, systemImage: marked ? "heart.slash" : "heart")
                    }

                    Button { onFile(track) } label: {
                        Label(Loc.get("Rpm_Track_AddToPlaylist"), systemImage: "text.badge.plus")
                    }
                }
            }
            // Swiping from the left moves the row right. This is the side the Uno app
            // and the queue list use for "play next". SwiftUI ignores swipe actions
            // where the row is not in a `List`, so the context menu above covers that
            // case.
            //
            // **The modifier is left off when there is no action, instead of being
            // given an empty group.** An empty `swipeActions` still claims that edge:
            // the row slides open with nothing under it and closes again, which looks
            // like a bug.
            .modifier(SendUpNext(deed: sender.map { put in { hearItNext(put) } }))

        if mine {
            row.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { onFile(track) } label: {
                    Label(Loc.get("Rpm_Track_AddToPlaylist"), systemImage: "text.badge.plus")
                }
                // Neutral colour. `RPMInk.red` is reserved for favourite, so the other
                // button must not compete with it.
                .tint(RPMInk.white(0x26 / 255))

                Button { mark() } label: {
                    Label(favourite, systemImage: marked ? "heart.slash" : "heart")
                }
                .tint(RPMInk.red)
            }
        } else {
            row
        }
    }

    /// The same action as the leading swipe, with the same label.
    @ViewBuilder
    private var playNext: some View {
        if let sender {
            Button { hearItNext(sender) } label: {
                Label(Loc.get("AlbumMenu_PlayNext"),
                      systemImage: "text.line.first.and.arrowtriangle.forward")
            }
        }
    }

    private func hearItNext(_ put: (CloudTrack) -> Void) {
        Haptics.commit()
        put(track)
    }

    /// The label names what pressing the button will do, not the current state. The
    /// desktop drawer does the same.
    private var favourite: String {
        Loc.get(marked ? "Track_UnsetFavorite" : "Track_SetFavorite")
    }

    private func mark() {
        Haptics.commit()
        onMark(track, !marked)
    }
}

/// The leading swipe action, **or no leading swipe at all**.
///
/// A `ViewBuilder` inside `swipeActions` cannot express "nothing on this side".
/// `swipeActions` with an empty body is not the same as no `swipeActions`: the empty one
/// still opens with nothing under the finger.
private struct SendUpNext: ViewModifier {
    let deed: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let deed {
            content.swipeActions(edge: .leading) {
                Button(action: deed) {
                    Label(Loc.get("AlbumMenu_PlayNext"),
                          systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .tint(RPMInk.white(0x33 / 255))
            }
        } else {
            content
        }
    }
}

/// The callbacks ``TrackActions`` needs, for a view that shows songs among other things
/// and passes them down to each song row. ``HomePicksRow`` is one: it shows albums,
/// playlists and stations next to songs.
///
/// **Every field is required**, for the reason ``TrackActions`` gives for `mine`. A view
/// that drew songs without these would show them without the menu, and nothing would
/// report it.
public struct TrackMenu {
    let isMarked: (CloudTrack) -> Bool
    let isMine: (CloudTrack) -> Bool
    let upNext: TrackActions.UpNext
    let onMark: (CloudTrack, Bool) -> Void
    let onFile: (CloudTrack) -> Void

    public init(isMarked: @escaping (CloudTrack) -> Bool,
                isMine: @escaping (CloudTrack) -> Bool,
                upNext: TrackActions.UpNext,
                onMark: @escaping (CloudTrack, Bool) -> Void,
                onFile: @escaping (CloudTrack) -> Void) {
        self.isMarked = isMarked
        self.isMine = isMine
        self.upNext = upNext
        self.onMark = onMark
        self.onFile = onFile
    }
}

public extension View {
    /// See ``TrackActions``.
    func trackActions(_ track: CloudTrack, marked: Bool, mine: Bool,
                      upNext: TrackActions.UpNext,
                      onMark: @escaping (CloudTrack, Bool) -> Void,
                      onFile: @escaping (CloudTrack) -> Void) -> some View {
        modifier(TrackActions(track: track, marked: marked, mine: mine,
                              upNext: upNext, onMark: onMark, onFile: onFile))
    }

    /// See ``TrackActions`` and ``TrackMenu``.
    func trackActions(_ track: CloudTrack, _ menu: TrackMenu) -> some View {
        trackActions(track, marked: menu.isMarked(track), mine: menu.isMine(track),
                     upNext: menu.upNext, onMark: menu.onMark, onFile: menu.onFile)
    }
}
