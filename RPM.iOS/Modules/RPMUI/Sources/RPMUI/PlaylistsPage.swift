import SwiftUI
import RPMSharedUI
import RPMSession
import RPMKit
import RPMLibrary

/// The playlists tab: the playlists that the computer keeps in the cloud, with the queue at the
/// top.
///
/// Ported from `RPM.Mobile/Presentation/PlaylistsPage.xaml`. The header uses the same type and
/// the same insets as the library's header, because this is a second view of the same
/// collection and not a different screen.
///
/// An existing playlist is shown here and cannot be edited. The computer owns these playlists:
/// its own database holds the track order, and each sync run writes the cloud copy again from
/// it. An edit made on the phone would be overwritten the next time that computer syncs. The
/// queue is the only list that this phone owns.
public struct PlaylistsPage: View {
    private let playlists: [PlaylistSet]
    private let queue: [CloudTrack]
    private let favorites: [CloudTrack]?
    private let covers: any CoverStore
    private let lender: String?
    private let standing: Standing

    /// The library to pick songs from, for the panel that the plus key opens. It is passed in and
    /// not fetched, because the tab that opens the panel already has the listing, and a second
    /// read would load the same listing again.
    private let albums: [CloudAlbum]

    /// Which view of the library is shown. The lists are one of three views, so the key that
    /// switches between them is in this header too. A view that the user can open but cannot
    /// leave could make them think their records have gone.
    @Binding private var mode: LibraryMode

    private let onOpen: (PlaylistRow) -> Void
    /// Reads the tree again. It is used by the retry key that appears when the first read failed,
    /// and by pull to refresh, for a list that may have changed on another device.
    private let onReread: () async -> Void

    /// Creates a playlist. Returns an error message when it failed, and nil when it is done.
    private let onMake: (String, [String], [CloudTrack]) async -> String?

    /// What the tab is doing when it is not showing rows: the state of the read that this page
    /// waits for. Shared with the TV app; see `RPMSession`.
    public typealias Standing = ReadStanding

    public init(playlists: [PlaylistSet], mode: Binding<LibraryMode>, queue: [CloudTrack],
                favorites: [CloudTrack]?,
                covers: any CoverStore, lender: String?, standing: Standing,
                albums: [CloudAlbum],
                onOpen: @escaping (PlaylistRow) -> Void,
                onReread: @escaping () async -> Void,
                onMake: @escaping (String, [String], [CloudTrack]) async -> String?) {
        self.playlists = playlists
        self._mode = mode
        self.queue = queue
        self.favorites = favorites
        self.covers = covers
        self.lender = lender
        self.standing = standing
        self.albums = albums
        self.onOpen = onOpen
        self.onReread = onReread
        self.onMake = onMake
    }

    /// The folder that the panel will create a new playlist in, or nil while the panel is
    /// closed. **It stores the folder and not a flag**, because the plus key that was tapped
    /// already says which folder the new playlist goes in.
    @State private var making: [String]?

    /// The folder that is open. **This is state of the page only.** No playlist is marked as
    /// open, and the tree does not know this value exists. The cost is that the value must be
    /// checked against the tree on every pass, which `PlaylistBrowse` does.
    @State private var at: [String] = []

    /// The layout of the lists. **It is saved between launches**, as the desktop app saves its
    /// own in its settings and as the records wall saves its order.
    @AppStorage("playlists.layout") private var layout: PlaylistLayout = .list

    /// How wide a tile is drawn on the grid. It is saved between launches, so the grid opens at
    /// the last size. It is separate from the records wall's value, because the two walls are
    /// pinched separately, and a user who wants large lists does not necessarily want large
    /// records.
    @AppStorage("playlists.tileArt.v1") private var stride: Double = 194

    /// The size that the fingers ask for while they are still on the screen. It is saved only
    /// when the fingers lift, because a size saved during a pinch is a value the user did not
    /// choose.
    @State private var pinching: Double?

    private var browse: PlaylistBrowse {
        PlaylistBrowse.of(at: at, playlists: playlists, queue: queue, favorites: favorites)
    }

    public var body: some View {
        let browse = self.browse

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                switch standing {
                case .reading:
                    waiting

                case .trouble(let what):
                    failed(what)

                case .showing:
                    switch layout {
                    case .list: list(browse)
                    case .grid: wall(browse)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollsUnder {
                VStack(spacing: 0) {
                    header(browse)
                    LibraryModeTabs($mode)
                }
            }
        }
        .background { VinylGround() }
        .overlay {
            if let folder = making {
                NewPlaylistSheet(
                    errand: .make(in: folder), albums: albums, covers: covers,
                    commit: { name, tracks in await onMake(name, folder, tracks) },
                    onClose: { making = nil })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: making == nil)
    }

    // ── the header ──

    private func header(_ browse: PlaylistBrowse) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // The back key, to the left of the folder name. It is shown only inside a folder. At
            // the top of the tree there is nowhere to go back to, and a key that does nothing is
            // worse than no key.
            if let back = browse.back {
                RPMBackKey(label: Loc.get("AddMusic_Back")) { Haptics.pick(); at = back }
                    .padding(.trailing, RPMBackKey.besideTitle)
            }

            PageHeading(browse.at.last ?? Loc.get("Playlists_Title"), line: counts(browse)) {
                EmptyView()
            }

            Spacer(minLength: 8)

            // The folder's keys on one glass capsule, as in the records wall's header.
            HStack(spacing: 0) {
                // Switches the same folder between covers and rows. It is placed next to the
                // keys that act on the folder, not in the menu that leaves the lists, because
                // it does neither of those things.
                PlaylistLayoutKey(layout: $layout)

                // In the header and not floating over the list: the list scrolls, and a button
                // that disappears when the user scrolls is hard to find again. It creates the
                // playlist in the folder that is open, which is the only way the phone lets
                // the user choose where a playlist goes.
                //
                // Hidden on a borrowed collection: a playlist created there would belong to
                // the user's own account but contain records they do not have, so it would
                // appear empty in every app that opened it.
                if lender == nil {
                    Button { making = browse.at } label: {
                        Text(Glyph.plus)
                            .font(RPMFont.icon(15))
                            .foregroundStyle(RPMInk.white(0xB8 / 255))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Loc.get("Playlists_NewPlaylist"))
                }
            }
            .rpmGlassGroup()

        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, 16)
        // No top padding: in the Uno phone app, SafeArea.Insets replaces the ten points that
        // its markup asks for, so its headers start at the safe area. See
        // `LibraryPage.header`. Ten points at the bottom, as in the other two views, so the
        // tabs under the header are at the same height on all three.
        .padding(.bottom, 10)
    }

    /// How much is here, and whose it is. The tab can show the contents of another user's
    /// collection, and nothing else would say so: the heading still reads Playlists and the rows
    /// look like the user's own.
    ///
    /// Inside a folder, the line starts with the folder's path: two folders called "90s" are two
    /// places, and the name alone does not show which one is open. The path is on this line and
    /// not on its own line above the title, so opening a folder does not push the tabs and the
    /// lists down.
    private func counts(_ browse: PlaylistBrowse) -> String {
        var parts: [String] = []
        if let lender, !lender.isEmpty { parts.append(Loc.get("Rpm_Share_SharedBy", lender)) }
        if !browse.path.isEmpty { parts.append(browse.path.joined(separator: " / ")) }

        parts.append(browse.rows.count == 1 ? Loc.get("Stats_PlaylistsOne")
                                            : Loc.get("Stats_Playlists", browse.rows.count))
        return parts.joined(separator: "  \u{b7}  ")
    }

    // ── what a press does ──

    /// A press on a folder opens the folder, and a press on anything else opens that item,
    /// whichever view the press came from. Both views use this one function, so a tile and a
    /// row always agree about what a tap on a list does.
    private func press(_ row: PlaylistRow) {
        if case .folder(let folder) = row.kind {
            Haptics.pick()
            at = folder.path
        } else {
            onOpen(row)
        }
    }

    // ── the rows ──

    @ViewBuilder
    private func list(_ browse: PlaylistBrowse) -> some View {
        // **Pull to refresh reads the tree again.** Playlists are created on a computer as
        // often as on the phone, so the user needs a way to ask for the current state. The
        // retry key appears only when the read has failed.
        DissolvingScroll {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(browse.rows) { row in
                    Button { press(row) } label: { line(row) }
                        .buttonStyle(RowPress())
                }

                footer(browse)

                Color.clear.frame(height: RPMLayout.foot)
            }
            // A folder is a new place, and a new place starts at the top. Without this, going
            // from the middle of a long folder into a short one would leave the scroll
            // position past the end of the short one.
            .id(browse.at)
        }
        .scrollIndicators(.hidden)
        .refreshable { await onReread() }
    }

    // ── the covers ──

    /// The same folder shown as covers: the desktop app's icon view, on the phone.
    ///
    /// The grid draws what is inside the open folder and nothing above it. This is the only
    /// difference from the rows layout. The header already shows where the folder is, so the
    /// grid draws no path over the tiles (the desktop app does). See ``PlaylistWall``.
    private func wall(_ browse: PlaylistBrowse) -> some View {
        PlaylistWall(
            rows: browse.rows, covers: covers,
            targetStride: pinching ?? Self.bounded(stride),
            onPress: press,
            onPinch: { factor in
                guard let factor else {
                    if let pinching { stride = pinching }
                    pinching = nil
                    return
                }
                pinching = Self.bounded(stride * factor)
            },
            footer: { footer(browse) })
            // A folder is a new place, and a new place starts at the top, as in the rows
            // layout.
            .id(browse.at)
            .refreshable { await onReread() }
    }

    /// The allowed range of a tile width, whether the value comes from a gesture or from the
    /// saved setting. These are the records wall's bounds. A fast pinch cannot ask for a wall
    /// a hundred tiles wide, and a value saved by another build cannot open the tab on a wall
    /// of one tile.
    private static func bounded(_ art: Double) -> Double { min(max(art, 60), 900) }

    /// The row from the computer's drawer, on the phone: the square cover, the name, and one
    /// quiet line under it. **There is no chevron except on a folder.** Every other row opens
    /// something, and a mark repeated on every row that behaves the same way only takes space
    /// from the names.
    private func line(_ row: PlaylistRow) -> some View {
        HStack(spacing: 12) {
            sleeve(row)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(detail(row))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.isFolder {
                Text(Glyph.into)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x55 / 255))
            }
        }
        .padding(.horizontal, RPMLayout.margin)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    /// The cover of the first item in the row, drawn as on the wall. A playlist without its own
    /// cover uses the record it starts with, which is the nearest thing to a cover.
    /// **A folder shows its glyph and nothing else.** A picture for a folder would describe one
    /// of the items inside it, not the folder.
    private func sleeve(_ row: PlaylistRow) -> some View {
        PlaylistSleeve(list: row.picture, track: row.artSource, glyph: row.mark,
                       edge: 44, corner: 6, mark: 16, covers: covers,
                       framed: FramedList.of(row.set))
    }

    private func detail(_ row: PlaylistRow) -> String {
        guard !row.isFolder else {
            return row.playlists == 1 ? Loc.get("Stats_PlaylistsOne")
                                      : Loc.get("Stats_Playlists", row.playlists)
        }
        return PlaylistWords.holding(row.tracks.count, row.duration, missing: row.missing)
    }

    // ── what to say when there are no rows ──

    @ViewBuilder
    private func footer(_ browse: PlaylistBrowse) -> some View {
        if !browse.at.isEmpty && browse.rows.isEmpty {
            // Only inside a folder that the user created. At the top of the tree an empty list
            // means that the account has no playlists at all, which the line under the queue
            // already says.
            Text(Loc.get("Playlists_FolderEmpty"))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else if browse.at.isEmpty && playlists.isEmpty && lender == nil {
            // Under the last row and not over the list. The queue can always be opened, and a
            // message over the middle of the list would hide it just to say that nothing else
            // has loaded.
            Text(Loc.get("Rpm_Playlists_EmptyHere"))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .padding(.horizontal, RPMLayout.margin)
                .padding(.top, 18)
        }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            RecordSpinner(diameter: 48)
            Text(lender.map { Loc.get("Rpm_Playlists_LoadingFrom", $0) }
                 ?? Loc.get("Rpm_Playlists_Loading"))
                .font(RPMFont.display(15))
                .foregroundStyle(RPMInk.white(0xCC / 255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ what: String) -> some View {
        VStack(spacing: 16) {
            Text(what)
                .font(RPMFont.display(15))
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .multilineTextAlignment(.center)

            Button(Loc.get("Rpm_Library_Retry")) { Task { await onReread() } }
                .buttonStyle(RPMGlassButton(.ghost, radius: 12, height: 44))
                .frame(width: 140)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── the square on every playlist row ──

/// The cover on a playlist row: a track's record, or a glyph.
///
/// This is a separate view and not a function, because it holds the picture. A `View` returned
/// from a method is rebuilt with its parent, and its fetch would run again every time the list
/// around it redraws.
struct PlaylistSleeve: View {
    /// The list's OWN picture, if it has one: the id it is stored under and the shelf it is on.
    /// Nil for a row that is not a stored list (the queue, the favourite songs, a folder) and for
    /// a list that uses the automatic cover.
    var list: ListPicture? = nil

    let track: CloudTrack?
    let glyph: String
    let edge: CGFloat
    let corner: CGFloat
    let mark: CGFloat
    let covers: any CoverStore

    /// The frame of a generated list, and nil for every other row. See ``FramedList``.
    var framed: FramedList? = nil

    /// Whether the room behind the window moves, for a list that has a room.
    ///
    /// **Every call site states it, and the default is not true.** The room is a shader that
    /// runs as long as the square is on screen, and the right answer depends on the surface. A few
    /// cards in a horizontal row can each run one, but a vertical list of forty rows cannot. The
    /// desktop app makes the same distinction: its row cards hold a live `CardRoom`, and its tree
    /// squares hold a composed picture of one.
    var roomDrifts: Bool = false

    @State private var cover: Cover?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        return ZStack {
            shape.fill(Color.black.opacity(0x22 / 255))
                .overlay { shape.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }

            if let framed, framed.look.roomed, RoomView.works {
                // The list has no picture of its own to put behind the window, so it is drawn on
                // the room. The same five lists have rooms in the desktop app, in the same colours.
                RoomView(colours: framed.room, sound: .still, foot: 1,
                         running: roomDrifts, breathes: true, zero: .whenShown,
                         seed: list?.id ?? framed.name)
                    .clipShape(shape)
            } else if let cover {
                Sleeve(image: cover.image)
                    .clipShape(shape)
                    .transition(.opacity)
            } else if framed == nil {
                Text(glyph)
                    .font(RPMFont.icon(mark))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: edge, height: edge)
        .listFrame(framed, edge: edge)
        .animation(.easeOut(duration: 0.2), value: cover != nil)
        // **The list's own picture comes first, and the cover of the first record is the
        // fallback.** A playlist can have a cover that the user chose or the app drew, and
        // that is the correct picture. The cover of the record that the list starts with is
        // used only when there is no own picture.
        // The size is part of the request, as the width band that the store groups sizes into
        // and not the exact width. On the wall, the square has whatever size the last pinch
        // gave it, and a tile that never asked again would keep its first picture at every
        // size. A row has one width and always gets the same band, so rows never ask again.
        .task(id: (list?.id ?? "") + "\u{1}" + (track?.rpmId ?? "")
                  + "\u{1}" + String(covers.band(for: edge))) {
            // Each answer is dropped if the task was cancelled while it was being made: the key
            // changed (a pinch moved the size band) or the square left the screen. Both requests
            // run off the main actor, so a replaced request can finish last and would otherwise
            // put the smaller picture back.
            if let list, let own = await covers.picture(of: list, edge: edge) {
                guard !Task.isCancelled else { return }
                cover = own
                return
            }

            guard let track else { cover = nil; return }
            let sleeve = await covers.cover(for: track, edge: edge)
            guard !Task.isCancelled else { return }
            cover = sleeve
        }
    }
}

// ── the words ──

/// Text that describes what a list holds, in the same wording as the desktop app.
public enum PlaylistWords {
    public static func holding(_ songs: Int, _ length: Duration, missing: Int) -> String {
        var said = songs == 1 ? Loc.get("Stats_SongsOne") : Loc.get("Stats_Songs", songs)

        if length > .zero { said += "  ·  " + runtime(length) }

        // A cloud playlist names tracks by id, and the computer uploads the order before the audio
        // has finished uploading. A playlist can therefore refer to tracks that the store does
        // not have yet. The count is shown, so the list does not look short without a reason.
        if missing > 0 {
            said += "  ·  " + (missing == 1
                ? Loc.get("Rpm_Playlist_MissingOne")
                : Loc.get("Rpm_Playlist_Missing", missing))
        }

        return said
    }

    public static func runtime(_ total: Duration) -> String {
        let seconds = Int(total.components.seconds)
        let hours = seconds / 3600

        guard hours >= 1 else { return minutes(seconds / 60) }

        let rest = (seconds % 3600) / 60

        // One localised sentence and not two parts joined by a comma. Each language decides
        // where the comma goes, or whether there is one.
        return hours == 1 ? Loc.get("Rpm_Playlists_LenHourOne", rest)
                          : Loc.get("Playlists_LenHours", hours, rest)
    }

    private static func minutes(_ count: Int) -> String {
        count == 1 ? Loc.get("Rpm_Playlists_LenMinuteOne") : Loc.get("Playlists_LenMinutes", count)
    }
}
