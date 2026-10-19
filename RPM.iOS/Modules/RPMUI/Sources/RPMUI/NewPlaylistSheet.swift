import SwiftUI
import RPMKit
import RPMLibrary

/// Makes a playlist, or adds songs to an existing one: the name and the songs are on one
/// panel.
///
/// Ported from `RPM.Mobile/Presentation/Controls/NewPlaylistSheet.xaml`. One panel serves
/// both tasks, because adding songs is the same panel without the name row.
///
/// **Cancel and the action key are in the header**, not at the bottom. Both text fields on
/// this panel open the keyboard, and the keyboard covers the bottom of the panel. A Create
/// button at the bottom would force the user to dismiss the keyboard before they can reach it.
///
/// There is no folder field. The folder is decided by *which* plus button was tapped, so
/// asking again here would ask the same question twice. Folders are made on the computer,
/// where the tree is.
public struct NewPlaylistSheet: View {
    /// What the panel is for. The title and the key on the right show which task it is.
    public enum Errand: Equatable, Sendable {
        /// A new playlist, created in this folder. An empty path is the top of the tree.
        case make(in: [String])

        /// Songs added to a playlist that already exists.
        case add(to: PlaylistSet)
    }

    private let errand: Errand
    private let albums: [CloudAlbum]
    private let covers: any CoverStore

    /// Does the saving. Returns a sentence when it failed and nil when it succeeded,
    /// because the panel has a line for a sentence and no place to show an error type.
    private let commit: (String, [CloudTrack]) async -> String?

    private let onClose: () -> Void

    public init(errand: Errand, albums: [CloudAlbum], covers: any CoverStore,
                commit: @escaping (String, [CloudTrack]) async -> String?,
                onClose: @escaping () -> Void) {
        self.errand = errand
        self.albums = albums
        self.covers = covers
        self.commit = commit
        self.onClose = onClose
    }

    @State private var name = ""
    @State private var asked = ""

    /// The songs picked, **in the order they were picked**. The playlist has the same order.
    @State private var chosen: [CloudTrack] = []

    /// The ids of the same songs, so that each drawn row can check quickly whether it is picked.
    @State private var chosenIds: Set<String> = []

    /// Whether the list shows the songs that were added, not the search results.
    @State private var showingAdded = false

    @State private var busy = false
    @State private var trouble: String?

    /// The search text after a short pause in typing. Searching on every keystroke would
    /// search the whole library once per letter.
    @State private var settled = ""

    /// The search results. **They are stored here and not computed in `body`**, as in the
    /// library tab's own search. `body` runs for many reasons unrelated to the search text,
    /// such as a song being added, a name being typed or a progress tick behind the panel.
    /// A search computed in `body` would walk the whole library on each of them.
    @State private var found: [SongSearch.SongHit] = []

    /// The space between the panel and the screen at the sides and the bottom.
    private static let margin: Double = 8

    @FocusState private var typing: Field?
    private enum Field { case name, search }

    public var body: some View {
        ZStack {
            // Tapping outside the panel cancels.
            Color.black.opacity(0xB3 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // The same space under the panel as at its sides, so its bottom edge stays
            // clear of the keyboard or the bottom of the screen.
            panel
                .padding([.horizontal, .bottom], Self.margin)
        }
        // The same pause and the same background search as the library tab's search. A
        // large collection must not be searched between two keystrokes, and never on the
        // main thread.
        .task(id: asked) {
            let asking = asked

            guard !asking.trimmingCharacters(in: .whitespaces).isEmpty else {
                found = []
                settled = asking
                return
            }

            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }

            let library = albums
            let hits = await Task.detached(priority: .userInitiated) {
                SongSearch.through(library, for: asking)
            }.value

            guard !Task.isCancelled else { return }

            found = hits
            settled = asking
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

            if asksForAName { nameRow }

            searchRow

            songs

            if let trouble {
                Text(trouble)
                    .font(RPMFont.display(12))
                    .foregroundStyle(Color(red: 1, green: 0xB4 / 255, blue: 0xA0 / 255))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .rpmGlassCard(radius: 18)
    }

    // ── the header ──

    private var header: some View {
        HStack(spacing: 8) {
            Button(Loc.get("Cloud_Cancel")) { onClose() }
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 38,
                                            stretches: false, inset: 14, size: 14))

            Text(title)
                .font(RPMFont.displayBold(17))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button(action: done) {
                if busy {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Text(action)
                }
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 38,
                                        stretches: false, inset: 14, size: 14))
            .disabled(!ready || busy)
            .opacity(ready && !busy ? 1 : 0.45)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var title: String {
        switch errand {
        case .make: return Loc.get("Playlists_NewPlaylist")
        case .add(let set): return set.name
        }
    }

    private var action: String {
        switch errand {
        case .make: return Loc.get("Rpm_NewPlaylist_Create")
        case .add: return Loc.get("Rpm_PlaylistPick_Add")
        }
    }

    /// The name row is shown only when there is a name to enter. The row is **removed**
    /// and not disabled, because a disabled field still has to be read.
    private var asksForAName: Bool {
        if case .make = errand { return true }
        return false
    }

    private var folder: [String] {
        switch errand {
        case .make(let into): return into
        case .add(let set): return set.folder
        }
    }

    /// Making a playlist needs a name, and adding songs needs at least one song. Nothing
    /// else is required: a playlist may be created with no songs and filled later.
    private var ready: Bool {
        switch errand {
        case .make: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .add: return !chosen.isEmpty
        }
    }

    // ── what it is called ──

    private var nameRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: $name,
                      prompt: Text(Loc.get("Rpm_NewPlaylist_Name")).foregroundStyle(RPMInk.white(0x77 / 255)))
                .rpmField()
                .focused($typing, equals: .name)
                .submitLabel(.done)

            // Shows which folder the playlist goes into, in a quiet style. At the top of
            // the tree there is nothing to show.
            if !folder.isEmpty {
                Text(Loc.get("Rpm_NewPlaylist_In", folder.joined(separator: " / "))).rpmKicker()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // ── the songs ──

    private var searchRow: some View {
        VStack(spacing: 8) {
            TextField("", text: $asked,
                      prompt: Text(Loc.get("Rpm_NewPlaylist_Search")).foregroundStyle(RPMInk.white(0x77 / 255)))
                .rpmField()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($typing, equals: .search)
                .submitLabel(.search)
                .onSubmit { typing = nil }
                // Typing switches away from the added-songs list. The box is a search
                // box, and a search that shows nothing because the added list is still
                // visible would look broken.
                .onChange(of: asked) { showingAdded = false }

            // **Chooses which of the two lists is shown below.** It is a segmented switch and
            // not a button, because the user wants to review the added songs, remove some
            // and look again, and choosing between two lists is what a switch is for.
            //
            // It is shown only once a song has been added. Before that there is no second
            // list, and a switch with an empty half would do nothing.
            if !chosen.isEmpty {
                Picker("", selection: $showingAdded) {
                    Text(Loc.get("Rpm_NewPlaylist_Results")).tag(false)
                    Text(Loc.get("Rpm_NewPlaylist_Added", chosen.count)).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.18), value: chosen.isEmpty)
    }

    @ViewBuilder
    private var songs: some View {
        let rows = showing

        if rows.isEmpty {
            Text(nothing)
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.track.rpmId) { row in
                        Button { pick(row.track) } label: { line(row) }
                            .buttonStyle(RowPress())
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var showing: [SongSearch.SongHit] {
        guard !showingAdded else {
            return chosen.map { SongSearch.SongHit(track: $0, album: SongSearch.albumOf($0, in: albums)) }
        }
        return found
    }

    private var nothing: String {
        if showingAdded { return Loc.get("Rpm_NewPlaylist_NoneAdded") }
        return settled.trimmingCharacters(in: .whitespaces).isEmpty
            ? Loc.get("Rpm_NewPlaylist_Start")
            : Loc.get("Rpm_NewPlaylist_NoResults")
    }

    private func line(_ row: SongSearch.SongHit) -> some View {
        let chosen = chosenIds.contains(row.track.rpmId)

        return HStack(spacing: 10) {
            PlaylistSleeve(track: row.track, glyph: Glyph.record, edge: 40,
                           corner: 6, mark: 16, covers: covers)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.track.title?.isEmpty == false ? row.track.title! : row.album.album)
                    .font(RPMFont.display(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // The track's own artist, and the album's artist only when the file has
                // none. On a compilation the two differ, and the track's artist is the one
                // the user is looking for.
                Text(said(row))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A plus shows what a tap will do, and a tick shows that the song is picked.
            Text(chosen ? "\u{f00c}" : Glyph.plus)
                .font(RPMFont.icon(15))
                .foregroundStyle(chosen ? RPMInk.white(0xE6 / 255) : RPMInk.white(0x66 / 255))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func said(_ row: SongSearch.SongHit) -> String {
        let artist = row.track.artist?.isEmpty == false ? row.track.artist! : row.album.artist
        let album = row.album.album

        switch (artist.isEmpty, album.isEmpty) {
        case (false, false): return "\(artist) · \(album)"
        case (false, true): return artist
        case (true, false): return album
        case (true, true): return ""
        }
    }

    private func pick(_ track: CloudTrack) {
        if chosenIds.remove(track.rpmId) != nil {
            chosen.removeAll { $0.rpmId == track.rpmId }
        } else {
            chosenIds.insert(track.rpmId)
            chosen.append(track)
        }
    }

    // ── making it ──

    private func done() {
        guard ready, !busy else { return }

        busy = true
        trouble = nil
        typing = nil

        Task {
            let said = await commit(name.trimmingCharacters(in: .whitespaces), chosen)
            busy = false

            guard let said else { onClose(); return }
            trouble = said
        }
    }
}
