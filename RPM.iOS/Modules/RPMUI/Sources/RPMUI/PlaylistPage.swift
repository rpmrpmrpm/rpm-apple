import SwiftUI
import RPMSharedUI
import QuartzCore
import RPMKit
import RPMLibrary
import RPMAudio
import RPMArt
import RPMStages

/// One list of songs: a stored playlist, the favourite songs, or the queue.
///
/// The layout is the same as ``AlbumPage``: the list's picture large and centred, the name, how
/// much is in the list, and the keys. All of these scroll away with the songs, and the back key
/// floats over the page. The page background is the list's own cover, blurred.
///
/// A stored playlist has Play and the round keys beside it. **The queue has no Play**, because
/// what is in it is already playing, or there is nothing to play. Its row has only the round
/// keys.
public struct PlaylistPage: View {
    private let title: String
    private let tracks: [CloudTrack]
    private let missing: Int
    private let covers: any CoverStore

    /// Whether this is the queue. The queue is the only list that this phone owns, so it is the
    /// only list whose rows can be removed.
    private let isQueue: Bool

    /// Which part of the list is on the screen, and which rows may be dragged where.
    ///
    /// **The caller states it. There is no default.** The queue is shown from the point where the
    /// current listening session began. If a record was started at track ten, the nine tracks
    /// above it were never played, and showing them would suggest that they were. The played part
    /// of the queue is not rearranged. A stored playlist is `.whole`: all of it is shown, and
    /// every row may be moved anywhere. See ``QueueLook``.
    private let look: QueueLook

    /// Whether the user can reorder the rows by dragging.
    ///
    /// True for the queue, and true for a stored playlist **when the phone can see all of its
    /// tracks**. A write sends the whole order, so a list with songs that this phone cannot
    /// identify would become shorter every time the user dragged a row. It is never true for
    /// another user's playlist, because the new order is written to the account that owns the
    /// list.
    private let canReorder: Bool

    /// The playlist that songs can be added to, or nil when songs cannot be added. The queue is
    /// filled by playing music, and the favourite songs are all songs that the user marked, so
    /// users do not add songs to either of them, and a plus key on them would have no meaning.
    /// It is also nil for another user's playlist, because adding a song would write to their
    /// account.
    private let adding: PlaylistSet?

    /// The library to pick from, for the panel that the plus key opens.
    private let albums: [CloudAlbum]

    private let playing: String?
    private let onPlay: (Int, Tapped) -> Void
    private let onShuffle: () -> Void
    private let onRemove: (IndexSet) -> Void

    /// Both positions are indices in `tracks`, and the target position is counted **after** the
    /// dragged row has been removed. The screen's own indices and the framework's insertion
    /// point stay in this file: ``QueueRows/drop(_:_:from:to:count:)`` translates them, and it
    /// has tests.
    private let onMove: (Int, Int) -> Void
    private let onBack: () -> Void

    /// Shows another selection of this list's songs, or nil when there is none.
    ///
    /// **Only a list that the computer generated has one**, and only while the run that the
    /// computer sent has more songs than are on the screen. This code does not cut the list. The
    /// computer sends enough songs for several lists, and this closure steps to the next slice,
    /// so the key responds in the same frame and works without a network signal. Nil removes the
    /// key, so there is no key that does nothing.
    private let onNewList: (() -> Void)?

    /// Adds songs to the playlist. Returns an error message when it failed, and nil when done.
    private let onAdd: (PlaylistSet, [CloudTrack]) async -> String?

    /// The list's own picture, if it has one: the id that the store keeps it under and the shelf
    /// it is on. Nil for the queue and the favourite songs, which have no cover, and then the
    /// header shows the cover of the first record in the list.
    private let picture: ListPicture?

    /// The list that this page shows, when the cloud holds a track order for it. Nil for the
    /// queue and the favourite songs.
    ///
    /// **It is held next to ``picture`` and does not replace it**, because the two answer
    /// different questions: where the cover is fetched from, and what the list IS. Only the frame
    /// of a generated list needs the second, and only the header reads it.
    private let showing: PlaylistSet?

    private let isTrackMarked: (CloudTrack) -> Bool

    /// Whether a song is on this account's own shelf.
    ///
    /// **There is no default, unlike `isTrackMarked`.** A borrowed song can be neither marked nor
    /// added to a playlist. The mark would be stored against an id that this account does not
    /// own, and a playlist names songs by id, so a song from another user's collection cannot be
    /// found here. This one answer decides whether those actions are offered, and a default
    /// would allow a page to be built without it.
    private let isTrackMine: (CloudTrack) -> Bool
    private let onMarkTrack: (CloudTrack, Bool) -> Void
    private let onFile: (CloudTrack) -> Void

    /// What "play after this song" means on these rows. **There is no default**, unlike the two
    /// parameters before it: this page shows the running order as well as stored lists, and the
    /// two cases need different answers. See ``TrackActions/UpNext``.
    private let upNext: TrackActions.UpNext

    public init(title: String, tracks: [CloudTrack], missing: Int,
                covers: any CoverStore, isQueue: Bool, look: QueueLook,
                canReorder: Bool = false,
                playing: String?,
                adding: PlaylistSet? = nil, albums: [CloudAlbum] = [],
                onPlay: @escaping (Int, Tapped) -> Void,
                onShuffle: @escaping () -> Void,
                onRemove: @escaping (IndexSet) -> Void,
                onMove: @escaping (Int, Int) -> Void,
                onBack: @escaping () -> Void,
                onNewList: (() -> Void)? = nil,
                onAdd: @escaping (PlaylistSet, [CloudTrack]) async -> String? = { _, _ in nil },
                picture: ListPicture? = nil,
                showing: PlaylistSet? = nil,
                isTrackMarked: @escaping (CloudTrack) -> Bool = { _ in false },
                isTrackMine: @escaping (CloudTrack) -> Bool,
                onMarkTrack: @escaping (CloudTrack, Bool) -> Void = { _, _ in },
                onFile: @escaping (CloudTrack) -> Void = { _ in },
                upNext: TrackActions.UpNext) {
        self.title = title
        self.tracks = tracks
        self.missing = missing
        self.covers = covers
        self.isQueue = isQueue
        self.look = look
        self.canReorder = canReorder
        self.adding = adding
        self.albums = albums
        self.playing = playing
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.onRemove = onRemove
        self.onMove = onMove
        self.onBack = onBack
        self.onNewList = onNewList
        self.onAdd = onAdd
        self.picture = picture
        self.showing = showing
        self.isTrackMarked = isTrackMarked
        self.isTrackMine = isTrackMine
        self.onMarkTrack = onMarkTrack
        self.onFile = onFile
        self.upNext = upNext
    }

    /// Whether the panel that picks songs is shown.
    @State private var picking = false

    /// Whether the list is in rearranging mode. On this platform rearranging is a mode and not a
    /// handle on every row.
    ///
    /// The Uno phone app draws a grip on every queue row and implements the drag itself, because
    /// Uno has no swipe actions and no reorder. iOS has both. The framework's reorder shows the
    /// grips only when the user turns rearranging on. That is acceptable, because the
    /// framework's gesture handling is better than a custom drag inside a scrolling list.
    @State private var rearranging = false

    /// The picture used for the whole page background: **this list's own cover and nothing
    /// else.**
    ///
    /// Nil when the list has no cover, and then the app's own background is used. A record from
    /// inside the list is not the list's picture. The square in the header falls back to a
    /// record because a square must show something, but the page background does not need to.
    /// The desktop app also removes its wash when the list has no cover, and does not borrow a
    /// record's cover: see `PlaylistView.ShowWashAsync`, and `PlaylistView.Lend`, which gives the
    /// same picture to the whole window.
    @State private var wash: Cover?

    /// The colours of the room behind the page, stored as a transition and not as a single
    /// value. The colours arrive a moment after the page, and the dissolve makes the change
    /// gradual. The app's own blue is used until they arrive. See ``RPMStages/RoomDissolve``.
    @State private var paint = RoomDissolve.still

    /// Whether the app is in the foreground. The square of a generated list moves only then,
    /// because a shader that keeps running in the background only heats the phone.
    @Environment(\.scenePhase) private var phase

    /// The rows on the screen: the whole list, or the part of the queue that the current
    /// listening session has reached. Every callback receives `row.at`, the position in
    /// `tracks`, and never the row's position on the screen.
    private var rows: [QueueRow] { QueueRows.of(tracks, look) }

    private var empty: Bool { rows.isEmpty }

    /// The width of the page, used for the size of the square at the top. It is measured from
    /// the background, where it does not affect the layout, for the reason that ``AlbumPage``
    /// gives.
    private struct PageWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @State private var width: CGFloat = 0

    /// **The layout is the same as the album page**: one `List` holds the top of the page and the
    /// songs, so the square, the name and the keys scroll away with the list, and the back key
    /// floats over it. It is a `List` because its rows can be removed and rearranged, and the
    /// framework's swipe and reorder work only inside a `List`.
    public var body: some View {
        List {
            header.scrollProbe().plainRow()

            if empty {
                nothing.plainRow()
            } else {
                songs
            }

            // The space at the bottom belongs to whatever is last on the page.
            Color.clear.frame(height: 40).plainRow()
        }
        .listStyle(.plain)
        // The rows are laid out at the width of the list and not the width of the cell, so a
        // swipe moves them and does not squeeze them. See ``View/rowsKeepTheirWidth()``.
        .rowsKeepTheirWidth()
        .scrollContentBackground(.hidden)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PageWidth.self, value: geometry.size.width)
            }
        }
        .environment(\.defaultMinListRowHeight, 1)
        .scrollIndicators(.hidden)
        // The list extends behind the status bar, and content that scrolls up behind the clock
        // and the back key fades into the page background there, as on the home page. This comes
        // before the backdrop and the back key, so the mask applies to the list and not to
        // anything placed over it, and the back key keeps the safe area.
        .ignoresSafeArea(edges: .top)
        .dissolvesAtTop(under: RPMSafeArea.top + RPMLayout.backRow)
        .onPreferenceChange(PageWidth.self) { width = $0 }
        .background { backdrop }
        .rpmFloatingBack(RPMBackKey(label: Loc.get("AddMusic_Back"), action: onBack))
        .environment(\.editMode, .constant(rearranging ? .active : .inactive))
        .overlay {
            if picking, let set = adding {
                NewPlaylistSheet(
                    errand: .add(to: set), albums: albums, covers: covers,
                    commit: { _, tracks in await onAdd(set, tracks) },
                    onClose: { picking = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: picking)
        .task(id: title) { await dress() }
    }

    /// The page background: **the list's room, moving**. It fills the whole page, as the album
    /// page's blurred cover does. A dark gradient over it keeps the rows readable whatever the
    /// room does. Where the room cannot be drawn, the list's own cover is used, blurred.
    @ViewBuilder
    private var backdrop: some View {
        if RoomView.works {
            // Inside a `Color.clear` and clipped: ``RoomView`` takes the size that it is offered,
            // and this keeps it at the size of the page.
            Color.clear
                .overlay {
                    RoomView(colours: paint, sound: .still, foot: 1,
                             running: phase == .active, breathes: true, zero: .whenShown,
                             seed: showing?.id ?? title)
                }
                .clipped()
                .overlay {
                    // Lighter at the top, where the square and the name are, and darker further
                    // down, where the rows are.
                    LinearGradient(
                        stops: [.init(color: .black.opacity(0x22 / 255), location: 0),
                                .init(color: .black.opacity(0x77 / 255), location: 0.45),
                                .init(color: .black.opacity(0x99 / 255), location: 1)],
                        startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
        } else {
            ArtGround(picture: wash?.image, accent: wash?.accent, showing: title,
                      colours: lit)
        }
    }

    /// The size of the cover, as on the album page: about six tenths of the page width, so the
    /// name, the count and the keys are visible without scrolling on the smallest phone that the
    /// app supports.
    private var coverEdge: CGFloat {
        min(max((width > 0 ? width : 390) * 0.62, 160), 360).rounded()
    }

    // ── the top of the page ──

    /// Loads the page's appearance: this list's own cover, and the colours of the room behind
    /// the page.
    ///
    /// **One read for both**, because they depend on each other: the colours are taken from the
    /// cover, as in the desktop app. A generated list has its own three colours, taken from what
    /// the list IS and not from any picture, and its frame uses the same three colours.
    private func dress() async {
        // This list's own cover, which is the only picture used for the page background. A
        // generated list is asked for it too: its photograph that is shipped with the app, or the
        // store's image, is the picture that its frame is cut around. The frame is drawn over
        // that picture and does not replace it.
        let own: Cover? = if let picture {
            await covers.picture(of: picture, edge: Self.washEdge)
        } else {
            nil
        }

        wash = own

        if let framed = FramedList.of(showing) {
            paint = framed.room
            return
        }

        // Use the colours of the list's own cover and nothing else: a record inside a list is not
        // the list's artwork. The desktop app takes the colours of its room from the list's cover
        // in the same way; see PlaylistView.OpenRoom. A list with no cover keeps the app's own
        // blue.
        guard let read = own?.colours else { return }

        paint = paint.toward(.from(tint: read.dominant?.asFloats,
                                   glow: read.highlight?.asFloats,
                                   shade: read.shade?.asFloats),
                             at: CACurrentMediaTime())
    }

    /// The colours of the page when the list has no cover at all: a generated list that has a
    /// room instead of a cover.
    ///
    /// These are the list's own three colours, which its frame also uses, so the square at the
    /// top of the page and the page background look like one list. It is empty for every other
    /// list, which uses its cover or the app's own background.
    private var lit: [Color] {
        guard let framed = FramedList.of(showing), framed.look.roomed else { return [] }
        return [framed.look.trio.hot.color, framed.look.trio.mid.color, framed.look.trio.deep.color]
    }

    /// The size at which the page's picture is loaded. It is small on purpose: the picture is
    /// blurred to a radius of sixty before it is shown, so a full-size decode would waste pixels.
    /// It is also the same size that is used to take the colours, so the background needs no
    /// second read.
    private static let washEdge: Double = 72

    /// The square, the name, how much is in the list, and the keys. This is the album page's top
    /// section, with the list's own picture where the album page has a cover.
    private var header: some View {
        VStack(spacing: 12) {
            // Space for the status bar and the back key, which floats and does not scroll with
            // the page. The list starts at the top of the screen.
            Color.clear.frame(height: RPMSafeArea.top + RPMLayout.backRow)

            sleeve

            Text(title)
                .font(RPMFont.displayBold(24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 10)

            // How much is in the list, shown as a chip, like the album page shows the length of
            // the record.
            Text(PlaylistWords.holding(rows.count, length, missing: missing))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0xE6 / 255))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(RPMInk.white(0x1F / 255)))

            // What the list is and who is on it: the line under the name in the desktop app. It is
            // placed where the album page puts its description, above the keys, in the same font.
            if let about {
                Text(about)
                    .font(AboutText.font)
                    .foregroundStyle(AboutText.ink)
                    .lineSpacing(AboutText.lineSpacing)
                    .multilineTextAlignment(.leading)
                    // One more line than the desktop app allows, because the column is narrower: a
                    // mood list's sentence and its names need about three lines on a phone.
                    .lineLimit(blurb == nil ? 2 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            keys
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, RPMLayout.margin)
        .padding(.bottom, 14)
    }

    /// The line under the name: a mood list's sentence, then "Featuring" and the artists. Nil for
    /// the queue, which is not a playlist, and for a list with nothing to show. See
    /// ``PlaylistFeatures/line(blurb:credits:)``. It is taken from the songs that this page
    /// shows, as the desktop app does with its rows, so it always agrees with them.
    private var about: String? {
        guard !isQueue else { return nil }
        return PlaylistFeatures.line(blurb: blurb, credits: tracks.map(\.artist))
    }

    /// The sentence for a generated mood list, or nil for any other list. See ``MoodBlurb``.
    private var blurb: String? {
        guard let showing, showing.origin == .generated, let cut = showing.cut else { return nil }
        return MoodBlurb.sentence(kind: cut.kind, genres: tracks.map { $0.tags?.genre })
    }

    /// The list's picture, square and centred, filling the whole square, like the album page's
    /// cover. The queue and the favourite songs have no cover, so they show the cover of the
    /// first record.
    private var sleeve: some View {
        PlaylistSleeve(list: picture, track: rows.first?.track, glyph: Glyph.record,
                       edge: coverEdge, corner: 4, mark: 52, covers: covers,
                       framed: FramedList.of(showing), roomDrifts: phase == .active)
    }

    /// Play, and the keys that always apply, as in the album page. **The queue has no Play**,
    /// because what is in it is already playing, or there is nothing to play. Its row has only
    /// the round keys, centred.
    ///
    /// The desktop app has one more key: it sends the whole set to the DJ and plays it as one run.
    /// It is not here because the mixer is not available in this app, and a key that does nothing
    /// is worse than no key.
    private var keys: some View {
        HStack(spacing: 10) {
            if !isQueue {
                Button { onPlay(rows.first?.at ?? 0, .list) } label: {
                    HStack(spacing: 10) {
                        Text(Glyph.play).font(RPMFont.icon(15))
                        Text(Loc.get("Rpm_Playlist_PlayList")).font(RPMFont.display(17))
                    }
                }
                .buttonStyle(RPMGlassButton(.primary, radius: 14, height: 50))
                .disabled(empty)
            }

            // Another selection of the same list, when the computer sent enough songs to make
            // one. It comes before shuffle, as in the desktop app: first what the list IS, then
            // what to do with it.
            if let onNewList {
                key(Glyph.refresh, Loc.get("Playlists_GenerateNew")) {
                    Haptics.pick()
                    onNewList()
                }
            }

            key(Glyph.shuffle, Loc.get("AlbumMenu_Shuffle"), action: onShuffle)
                .disabled(empty)

            // Add more songs to this list. It opens the same panel as the plus key on the tab,
            // but the name is already known.
            if adding != nil {
                key(Glyph.plus, Loc.get("Rpm_Playlist_AddSongs")) { picking = true }
            }

            // Shown only when there is something to rearrange, and only where this phone may
            // write the order. While rearranging, the key shows a tick to leave the mode. It does
            // not show a play mark, because a play glyph would mean "play this", which this key
            // does not do.
            if canReorder && rows.count > 1 {
                key(rearranging ? "\u{f00c}" : Glyph.grip,
                    rearranging ? Loc.get("CloudChip_StageDone") : Loc.get("Rpm_Queue_Rearrange")) {
                    Haptics.pick()
                    withAnimation { rearranging.toggle() }
                }
            }
        }
        .padding(.top, 6)
    }

    /// One of the round keys beside Play, like the shuffle and heart keys on the album page.
    private func key(_ glyph: String, _ said: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(RPMFont.icon(17))
        }
        .buttonStyle(RPMGlassButton(.ghost, radius: 14, height: 50))
        .frame(width: 56)
        .accessibilityLabel(said)
    }

    /// The total duration of the rows on the screen.
    private var length: Duration {
        .seconds(rows.reduce(0.0) { $0 + ($1.track.tags?.durationSeconds ?? 0) })
    }

    // ── the songs ──

    /// The songs, as rows of the page's list.
    @ViewBuilder
    private var songs: some View {
        // **Identity, position and place on the screen are three different things**, and
        // ``QueueRows`` keeps them apart. If a row is identified by its position, it keeps that
        // identity through a reorder but gets the contents of a different song. While the list
        // animates this, it draws two rows in one place and a gap where the third was.
        ForEach(rows) { row in
            Button { onPlay(row.at, .song) } label: { self.row(row.track) }
                .buttonStyle(RowPress())
                .trackActions(row.track, marked: isTrackMarked(row.track),
                              mine: isTrackMine(row.track), upNext: upNext,
                              onMark: onMarkTrack, onFile: onFile)
                .plainRow()
                // A running order is changed only after the current position: songs that were
                // already played are not rearranged, and neither is the song that is playing. A
                // stored playlist has no current position, so every row can move.
                .moveDisabled(!canReorder || row.state != .coming)
                // **Both of these are only for the queue, and neither is attached anywhere else.**
                // An empty `swipeActions` is not the same as no `swipeActions`: the edge is still
                // claimed, and the row opens a little with nothing behind it and closes again. A
                // stored playlist has no swipe keys, so it must not claim the edges either.
                .modifier(QueueRowKeys(
                    on: isQueue, playing: look.playing, at: row.at,
                    remove: { onRemove(IndexSet(integer: row.at)) },
                    move: onMove))
        }
        .onMove { from, to in
            // Positions within this `ForEach`, not within the whole list: the top section of the
            // page above it is not counted.
            guard let plan = QueueRows.drop(rows, look, from: from, to: to,
                                            count: tracks.count) else { return }
            Haptics.tick()
            onMove(plan.from, plan.to)
        }
    }

    /// The album page's row, with the record's own cover where the album page has a track number.
    /// The songs of a playlist come from many records, and the cover shows which record a song
    /// is from.
    private func row(_ track: CloudTrack) -> some View {
        HStack(spacing: 14) {
            // The playing mark in the margin: three points wide and white, which is how "playing"
            // is shown everywhere in this app.
            Rectangle()
                .fill(track.rpmId == playing ? Color.white : .clear)
                .frame(width: 3, height: 28)
                .clipShape(Capsule())

            PlaylistSleeve(track: track, glyph: Glyph.record, edge: 40,
                           corner: 6, mark: 16, covers: covers)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(track.title ?? "")
                        .font(RPMFont.display(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // The E (explicit) mark after the title, inside the layout, so a long title is
                    // shortened to leave room for it and does not run under it.
                    if track.isExplicit {
                        Text("E")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RPMInk.ground)
                            .frame(width: 14, height: 14)
                            .background(RoundedRectangle(cornerRadius: 3).fill(RPMInk.white(0xAA / 255)))
                    }
                }

                Text(said(track))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0x77 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(AlbumPage.length(track.duration))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        // A swipe makes the cell narrower, but this row keeps its width. See
        // ``View/keepsItsWidth()``.
        .keepsItsWidth()
    }

    /// Artist and album on one line, as in the mini player.
    private func said(_ track: CloudTrack) -> String {
        let artist = track.artist ?? ""
        let album = track.album ?? ""

        switch (artist.isEmpty, album.isEmpty) {
        case (false, false): return "\(artist) · \(album)"
        case (false, true): return artist
        case (true, false): return album
        case (true, true): return ""
        }
    }

    // ── nothing to list ──

    /// **It shows why the list is empty, not only that it is empty.** There are three different
    /// cases, and each needs a different message: a playlist whose tracks have not finished
    /// uploading, a playlist that has no songs yet, and the queue, which is not a playlist.
    private var nothing: some View {
        Text(isQueue
             ? Loc.get("Rpm_Queue_Empty")
             : missing > 0
               ? PlaylistWords.waitingOn(missing)
               : adding != nil
                 ? Loc.get("Rpm_Playlist_Empty")
                 : Loc.get("Rpm_Playlist_EmptyPlain"))
            .font(RPMFont.display(15))
            .foregroundStyle(RPMInk.white(0xCC / 255))
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension PlaylistWords {
    /// The message for tracks that are in a playlist but not in the store yet. This can happen:
    /// the cloud names tracks by id, and the computer uploads the running order before the audio
    /// has finished uploading.
    public static func waitingOn(_ missing: Int) -> String {
        missing == 1
            ? Loc.get("Rpm_Playlist_MissingOne")
            : Loc.get("Rpm_Playlist_Missing", missing)
    }
}

/// The two swipe keys of a row in the **running order**. A row that is not in a running order
/// gets no swipe edges at all.
///
/// They are the same two keys as in the queue panel over the player, in the same places with the
/// same words: swipe the row right to play it after the current song, and left to remove it.
/// See ``QueueOverlay``, which is the other list that shows the same queue. The same action
/// must look the same in both places, or the user would see two different actions.
private struct QueueRowKeys: ViewModifier {
    let on: Bool

    /// The index of the song that is playing, which both keys are measured from.
    let playing: Int?

    /// This row's position in the queue itself, never its position on the screen.
    let at: Int

    let remove: () -> Void
    let move: (Int, Int) -> Void

    /// Whether moving this row up to just after the playing song would change anything. The
    /// playing song cannot be put after itself, and the song that is already next is already
    /// there. In both cases the key would promise an action and then do nothing.
    private var canMoveUp: Bool { at != playing && at != (playing ?? -1) + 1 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            // The trailing key is on every row of a running order. The leading key is not, and
            // where it is missing, the edge is left out and not left empty.
            let row = content.swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Haptics.commit()
                    remove()
                } label: {
                    Label(Loc.get("Details_RemoveArt"), systemImage: "trash")
                }
            }

            if canMoveUp {
                row.swipeActions(edge: .leading) {
                    Button {
                        Haptics.commit()
                        move(at, (playing ?? -1) + 1)
                    } label: {
                        Label(Loc.get("AlbumMenu_PlayNext"),
                              systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(RPMInk.white(0x33 / 255))
                }
            } else {
                row
            }
        } else {
            content
        }
    }
}
