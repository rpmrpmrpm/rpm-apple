import SwiftUI
import RPMKit
import RPMLibrary
import RPMRadio

/// What a long press offers beyond a song's own menu: what the person put on home's Quick
/// selection, the playlists they pinned to the top of the playlists tab, play next for a record,
/// and, on a station, a pin to the radio home's Quick selection and the saved stations.
///
/// One for the app, made by the root and handed down in the environment. Every view that offers
/// these reads it there (`@Environment(Holds.self)`, optional), so a view drawn without one, in a
/// preview or on another head, offers nothing extra rather than stopping the app.
///
/// The lists are kept in the standard user defaults under the keys the Android phone uses.
@MainActor
@Observable
public final class Holds {
    /// What the person added to Quick selection, newest first, as ``QuickRefs`` writes them.
    public private(set) var quickAdded: [String]

    /// The ids of the playlists pinned to the top of the playlists tab, in the order they were
    /// pinned.
    public private(set) var pinned: [String]

    /// The stations pinned to the radio home's Quick selection, in the order they were pinned.
    ///
    /// **Each is kept whole**, as a saved station is, so it is shown and plays when the directory
    /// does not answer. It is kept as the directory files it: the folded entries, the shown name
    /// and the admin's edit are not saved (``RadioStation``'s coding leaves them out) and are
    /// worked out again when it is drawn.
    public private(set) var pinnedStations: [RadioStation]

    /// Puts a record's songs after the song that is playing, as play next does for one song.
    private let playNextRecord: @MainActor (CloudAlbum) -> Void

    /// The saved stations the radio shows, and whether they may change here. On a shared
    /// collection they are its owner's and are never changed (``SavedStations``).
    private let savedStations: @MainActor () -> SavedStations

    /// Saves a station, or takes it out of the saved stations.
    private let toggleSaved: @MainActor (RadioStation) -> Void

    private let store: UserDefaults

    /// Where Quick selection's own picks are kept.
    public static let quickKey = "home.quick"

    /// Where the pinned playlists are kept.
    public static let pinnedKey = "playlists.pinned"

    /// Where the pinned stations are kept, as JSON.
    public static let pinnedStationsKey = "radio.pinned"

    /// The most stations the person can pin: the radio home's Quick selection shows sixteen lines
    /// in all (``RadioHomePicks/quickMost``).
    public static let pinnedStationsMost = RadioHomePicks.quickMost

    /// - Parameters:
    ///   - savedStations: the saved stations the radio shows. Read when a station's menu is drawn.
    ///   - toggleSaved: saves a station or unsaves it. Called only where `savedStations` may
    ///     change.
    public init(store: UserDefaults = .standard,
                playNext: @escaping @MainActor (CloudAlbum) -> Void,
                savedStations: @escaping @MainActor () -> SavedStations = { .reading },
                toggleSaved: @escaping @MainActor (RadioStation) -> Void = { _ in }) {
        self.store = store
        self.playNextRecord = playNext
        self.savedStations = savedStations
        self.toggleSaved = toggleSaved
        quickAdded = store.stringArray(forKey: Self.quickKey) ?? []
        pinned = store.stringArray(forKey: Self.pinnedKey) ?? []
        pinnedStations = Self.readStations(store.data(forKey: Self.pinnedStationsKey))
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

    // ── a station ──

    /// Whether `station` is pinned, by its uuid or one of the entries folded into it.
    public func isPinned(_ station: RadioStation) -> Bool {
        pinnedStations.contains { station.isFiled(as: $0.uuid) }
    }

    /// Pins `station` after the others, or unpins it. At most ``pinnedStationsMost``: the oldest
    /// pin goes first.
    public func pinStation(_ station: RadioStation, _ on: Bool) {
        let others = pinnedStations.filter { !station.isFiled(as: $0.uuid) }
        var kept = station
        kept.shownName = nil
        kept.otherLogos = []
        kept.alsoFiledAs = []
        kept.edit = nil
        pinnedStations = on ? Array((others + [kept]).suffix(Self.pinnedStationsMost)) : others
        if let data = try? JSONEncoder().encode(pinnedStations) {
            store.set(data, forKey: Self.pinnedStationsKey)
        }
    }

    /// The saved stations, read now. See ``savedStations``.
    func saved() -> SavedStations { savedStations() }

    /// Saves `station` or unsaves it, where the saved stations may change.
    func toggleSave(_ station: RadioStation) {
        guard savedStations().mayChange else { return }
        toggleSaved(station)
    }

    private static func readStations(_ data: Data?) -> [RadioStation] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([RadioStation].self, from: data)) ?? []
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

/// The long-press menu on a record, wherever one is shown: play next, and Quick selection. A
/// starter record is not offered for Quick selection: it goes away once the person has music of
/// their own (``StarterTracks``).
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

                if !StarterTracks.isStarter(album) {
                    HoldItems.quick(holds, ref: QuickRefs.of(album: album.key))
                }
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

/// The long-press menu on a station, wherever one is shown on the radio tab: pin it to the radio
/// home's Quick selection or unpin it, and save it or take it out of the saved stations. Saving is
/// offered only for the person's own saved stations: on a shared collection they are the owner's.
private struct StationHold: ViewModifier {
    let station: RadioStation

    @Environment(Holds.self) private var holds: Holds?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let holds {
            content.contextMenu {
                let pinned = holds.isPinned(station)
                Button {
                    Haptics.commit()
                    holds.pinStation(station, !pinned)
                } label: {
                    Label(Loc.get(pinned ? "Radio_Unpin" : "Radio_Pin"),
                          systemImage: pinned ? "pin.slash" : "pin")
                }

                let saved = holds.saved()
                if saved.mayChange {
                    let isSaved = saved.stations.contains { station.isFiled(as: $0.uuid) }
                    Button {
                        Haptics.commit()
                        holds.toggleSave(station)
                    } label: {
                        Label(Loc.get(isSaved ? "Radio_Unsave" : "Radio_Save"),
                              systemImage: isSaved ? "heart.slash" : "heart")
                    }
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// The long-press menu on a station. See ``Holds``.
    func stationHold(_ station: RadioStation) -> some View { modifier(StationHold(station: station)) }

    /// The long-press menu on a record. See ``Holds``.
    func albumHold(_ album: CloudAlbum) -> some View { modifier(AlbumHold(album: album)) }

    /// The long-press menu on a playlist, or nothing where `list` is nil. See ``Holds``.
    func listHold(_ list: PlaylistSet?) -> some View { modifier(ListHold(list: list)) }
}
