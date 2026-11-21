import SwiftUI
import RPMKit
import RPMLibrary

/// What a long press offers beyond a song's own menu: what the person put on home's Quick
/// selection, the playlists they pinned to the top of the playlists tab, and play next for a
/// record.
///
/// One for the app, made by the root and handed down in the environment. Every view that offers
/// these reads it there (`@Environment(Holds.self)`, optional), so a view drawn without one, in a
/// preview or on another head, offers nothing extra rather than stopping the app.
///
/// Both lists are kept in the standard user defaults under the keys the Android phone uses.
@MainActor
@Observable
public final class Holds {
    /// What the person added to Quick selection, newest first, as ``QuickRefs`` writes them.
    public private(set) var quickAdded: [String]

    /// The ids of the playlists pinned to the top of the playlists tab, in the order they were
    /// pinned.
    public private(set) var pinned: [String]

    /// Puts a record's songs after the song that is playing, as play next does for one song.
    private let playNextRecord: @MainActor (CloudAlbum) -> Void

    private let store: UserDefaults

    /// Where Quick selection's own picks are kept.
    public static let quickKey = "home.quick"

    /// Where the pinned playlists are kept.
    public static let pinnedKey = "playlists.pinned"

    public init(store: UserDefaults = .standard,
                playNext: @escaping @MainActor (CloudAlbum) -> Void) {
        self.store = store
        self.playNextRecord = playNext
        quickAdded = store.stringArray(forKey: Self.quickKey) ?? []
        pinned = store.stringArray(forKey: Self.pinnedKey) ?? []
    }

    // ── Quick selection ──

    public func isQuick(_ ref: String) -> Bool { quickAdded.contains(ref) }

    /// Adds to Quick selection, or takes out what the person put there.
    public func toggleQuick(_ ref: String) {
        quickAdded = isQuick(ref) ? QuickRefs.removing(ref, from: quickAdded)
                                  : QuickRefs.adding(ref, to: quickAdded)
        store.set(quickAdded, forKey: Self.quickKey)
    }

    // ── pins ──

    public func isPinned(_ id: String) -> Bool { pinned.contains(id) }

    /// Pins a list to the top of the playlists tab, after the ones pinned before it, or lets it go
    /// back to its own place.
    public func togglePin(_ id: String) {
        pinned = isPinned(id) ? pinned.filter { $0 != id } : pinned.filter { $0 != id } + [id]
        store.set(pinned, forKey: Self.pinnedKey)
    }

    // ── a record ──

    func playNext(_ album: CloudAlbum) { playNextRecord(album) }
}

/// The words and marks of the items a hold adds, the same on every menu that carries them.
enum HoldItems {
    /// Add to Quick selection, or Remove from it where the person already added it.
    @MainActor
    static func quick(_ holds: Holds, ref: String) -> some View {
        let on = holds.isQuick(ref)
        return Button {
            Haptics.commit()
            holds.toggleQuick(ref)
        } label: {
            Label(Loc.get(on ? "Home_RemoveFromQuick" : "Home_AddToQuick"),
                  systemImage: on ? "bolt.slash" : "bolt")
        }
    }

    /// Pin to the top, or Unpin where the list is pinned.
    @MainActor
    static func pin(_ holds: Holds, id: String) -> some View {
        let on = holds.isPinned(id)
        return Button {
            Haptics.commit()
            holds.togglePin(id)
        } label: {
            Label(Loc.get(on ? "Playlists_Unpin" : "Playlists_Pin"),
                  systemImage: on ? "pin.slash" : "pin")
        }
    }
}

/// The long-press menu on a record, wherever one is shown: play next, and Quick selection.
private struct AlbumHold: ViewModifier {
    let album: CloudAlbum

    @Environment(Holds.self) private var holds: Holds?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let holds {
            content.contextMenu {
                Button {
                    Haptics.commit()
                    holds.playNext(album)
                } label: {
                    Label(Loc.get("AlbumMenu_PlayNext"),
                          systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                HoldItems.quick(holds, ref: QuickRefs.of(album: album.key))
            }
        } else {
            content
        }
    }
}

/// The long-press menu on a playlist, wherever one is shown: pinned to the top of the playlists
/// tab, and Quick selection. Nothing for a row that is not a list (the queue, the marked songs, a
/// folder), which is passed as nil.
private struct ListHold: ViewModifier {
    let list: PlaylistSet?

    @Environment(Holds.self) private var holds: Holds?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let holds, let list {
            content.contextMenu {
                HoldItems.pin(holds, id: list.id)
                HoldItems.quick(holds, ref: QuickRefs.of(list: list.id))
            }
        } else {
            content
        }
    }
}

extension View {
    /// The long-press menu on a record. See ``Holds``.
    func albumHold(_ album: CloudAlbum) -> some View { modifier(AlbumHold(album: album)) }

    /// The long-press menu on a playlist, or nothing where `list` is nil. See ``Holds``.
    func listHold(_ list: PlaylistSet?) -> some View { modifier(ListHold(list: list)) }
}
