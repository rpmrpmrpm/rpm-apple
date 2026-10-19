import SwiftUI
import RPMSharedUI
import RPMSession
import RPMKit
import RPMLibrary
import RPMDesign

/// The wall of records. The phone cannot edit the library, so the user can only do two
/// things to it: change the order, and read it again.
///
/// Ported from `RPM.Mobile/Presentation/LibraryPage.xaml`. The header has the title, the
/// counts, and the keys on the same line as the title. The keys sit on the app's own
/// background, so they have no background of their own.
public struct LibraryPage: View {
    /// Where the read that this page waits on stands. Shared with the TV app; see
    /// `RPMSession`.
    ///
    /// **It is an explicit state, because an empty array can mean three different things:**
    /// the library is really empty, the read has not finished, or the read failed. Only the
    /// first should show "nothing here yet, upload your library from rpm on your computer".
    /// The other two show a spinner and an error sentence. The message would also be wrong
    /// for a shared collection that belongs to someone else.
    public typealias Standing = ReadStanding

    private let standing: Standing
    private let albums: [CloudAlbum]
    private let covers: any CoverStore
    private let playing: String?
    private let onOpen: (CloudAlbum) -> Void
    private let onPlay: (CloudTrack) -> Void
    private let onRefresh: () async -> Void

    /// Whether a song found by searching is marked. The actions below are for songs found
    /// by searching only. The wall has no such menu, because a record is opened and not
    /// filed.
    private let isTrackMarked: (CloudTrack) -> Bool

    /// Whether a song is on this account's own shelf.
    ///
    /// **It has no default value, unlike the mark beside it.** A song from a shared
    /// collection can be neither marked nor filed. The mark would be stored against an id
    /// that this account does not own, and a playlist names songs by id, so a song from
    /// someone else's collection would resolve to nothing here. This one answer decides
    /// whether those actions are offered, and a default would let a page be built without
    /// it.
    private let isTrackMine: (CloudTrack) -> Bool
    private let onMarkTrack: (CloudTrack, Bool) -> Void
    private let onFile: (CloudTrack) -> Void

    /// What "play after this one" means on these rows. See ``TrackActions/UpNext``.
    private let upNext: TrackActions.UpNext

    /// Whose collection is on the wall, or nil for the user's own. **It is a name and not
    /// a flag**, because a shared wall needs to show whose it is.
    private let lender: String?

    /// Keeps the wall's order between visits to the tab.
    ///
    /// **The shell owns it and passes it in**, because a tab is discarded when the user
    /// leaves it. If it were kept here, returning to the library would sort the whole
    /// collection again for no reason. See ``SortedWall``.
    private let inOrder: SortedWall

    /// Which view of the library the tab shows. It is a binding and not state, because the
    /// artists page has the same key, and switching there must be able to return here.
    @Binding private var mode: LibraryMode

    public init(albums: [CloudAlbum], standing: Standing,
                covers: any CoverStore, playing: String?,
                inOrder: SortedWall, mode: Binding<LibraryMode>,
                lender: String? = nil,
                onOpen: @escaping (CloudAlbum) -> Void,
                onPlay: @escaping (CloudTrack) -> Void,
                onRefresh: @escaping () async -> Void,
                isTrackMarked: @escaping (CloudTrack) -> Bool = { _ in false },
                isTrackMine: @escaping (CloudTrack) -> Bool,
                onMarkTrack: @escaping (CloudTrack, Bool) -> Void = { _, _ in },
                onFile: @escaping (CloudTrack) -> Void = { _ in },
                upNext: TrackActions.UpNext) {
        self.isTrackMarked = isTrackMarked
        self.isTrackMine = isTrackMine
        self.onMarkTrack = onMarkTrack
        self.onFile = onFile
        self.upNext = upNext
        self.inOrder = inOrder
        _mode = mode
        self.lender = lender
        self.albums = albums
        self.standing = standing
        self.covers = covers
        self.playing = playing
        self.onOpen = onOpen
        self.onPlay = onPlay
        self.onRefresh = onRefresh
    }

    /// The search field is hidden until the user asks for it, as in Mail and Photos. The
    /// phone's library is a wall of covers, and search is a secondary action.
    @State private var searching = false
    @State private var asked = ""

    /// The order of the wall. **It is saved between launches**, as the desktop app saves it
    /// in its settings. The order is a way of viewing the collection, and the user should
    /// not have to choose it again every time the app opens.
    @AppStorage("library.order") private var order: AlbumOrdering = .artist

    /// The songs that the search found.
    ///
    /// **They are stored and not computed in `body`.** A search walks every track in the
    /// library, and `body` runs for reasons unrelated to the search text: a progress tick,
    /// the keyboard appearing, or a record starting elsewhere in the app.
    @State private var found: [SongSearch.SongHit] = []

    /// The records that the same search text found. They are a separate result and not a
    /// subset of the songs: "the album Hex" is not the same as "everything on Hex". They are
    /// shown above the songs, because a user who types a record's name is looking for the
    /// record and should not have to scroll past forty of its tracks.
    @State private var records: [CloudAlbum] = []

    @State private var settled = ""

    /// The width of a card. It is saved between launches, so the wall opens at the size the
    /// user left it. It is stored in `UserDefaults` and not in the app's own `Prefs`, which
    /// this module cannot see, and it is one value written once per gesture.
    ///
    /// **The key name contains a version**, as in the Uno app. The default changes when the
    /// wall's padding changes, and a phone where the user had ever pinched would otherwise
    /// keep the old size for ever. Bumping the version resets the saved size once.
    @AppStorage("library.tileArt.v2") private var stride: Double = 194

    /// The size requested by the pinch while the fingers are still on the screen. It is
    /// saved only when the fingers lift, so a size from the middle of a pinch is never
    /// stored.
    @State private var pinching: Double?

    @FocusState private var typing: Bool

    public var body: some View {
        VStack(spacing: 0) {
            // **The header has `zIndex(1)` so it is drawn in front of the field.** A stack
            // draws in the order it is written, so without this the field would slide
            // across the title instead of out from under it.
            VStack(spacing: 0) {
                if searching && !asked.isEmpty {
                    results
                } else {
                    switch standing {
                    case .reading: waiting
                    case .trouble(let said): failed(said)
                    case .showing: wall
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollsUnder {
                VStack(spacing: 0) {
                    header.zIndex(1)
                    if searching { field }
                    LibraryModeTabs($mode)
                }
            }
        }
        .background { VinylGround() }
        // **A keystroke does not start a search.** Searching the whole library on every
        // letter would make the interface stutter while the user types. This waits for
        // the typing to pause, and then searches off the main thread, so that even a
        // large collection cannot drop a frame.
        //
        // The wall is part of the search key, not only the text: if the library arrives
        // while the user is typing, the search must run again.
        .task(id: Hunt(asked: asked, wall: ordered)) {
            let asking = asked

            guard !asking.trimmingCharacters(in: .whitespaces).isEmpty else {
                found = []
                records = []
                settled = asking
                return
            }

            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }

            let library = ordered
            let began = Date()
            let hits = await Self.look(through: library, for: asking)

            guard !Task.isCancelled else { return }

            MainActorWatch.searched(albums: library.count, hits: hits.songs.count,
                                    records: hits.records.count,
                                    took: Date().timeIntervalSince(began),
                                    sorts: inOrder.sorts)

            records = hits.records
            found = hits.songs
            settled = asking
        }
    }

    /// Runs both searches off the main actor, **as a child of the search task that asked
    /// for them**, so a new keystroke during the search cancels it.
    ///
    /// **Do not use `Task.detached` here.** A detached task has no parent, so cancelling the
    /// `.task` when the text changes would not reach it. The search would then run to the
    /// end of the library for a query that nobody needs any more, and the closure that
    /// called it would stay suspended until it finished. Typing with a normal pause between
    /// letters would put one such task on the thread pool per letter, each walking
    /// thousands of songs (about 17,000 in a large library) while the main actor draws the
    /// keyboard.
    ///
    /// `nonisolated` is enough to leave the main actor: an async function that is not
    /// actor-isolated does not run on its caller's actor. Because it is an ordinary child
    /// call, cancellation reaches it, and `SongSearch` checks for cancellation per record.
    ///
    /// Both searches run in one hop. With two hops, the records would appear a frame before
    /// the songs, and the list would grow under the finger of a user who is still typing.
    private nonisolated static func look(
        through library: [CloudAlbum], for asking: String
    ) async -> (records: [CloudAlbum], songs: [SongSearch.SongHit]) {
        (records: SongSearch.records(library, for: asking),
         songs: SongSearch.through(library, for: asking))
    }

    /// Leaves the search completely: clears the text and the results, hides the box and
    /// dismisses the keyboard.
    ///
    /// **The text is cleared together with the box.** Opening the search again starts a new
    /// search and does not show the previous text, and results left behind a closed box
    /// would show the answer to a query that is no longer visible.
    private func closeSearch() {
        asked = ""
        settled = ""
        found = []
        typing = false
        withAnimation(.easeOut(duration: 0.22)) { searching = false }
    }

    /// The search field. It slides out from under the header, and its text is cleared when
    /// it closes.
    ///
    /// **There are two cross buttons, and they do different things.** The one INSIDE the box
    /// clears the text, which is what a cross inside a field means everywhere else in the
    /// app. The one beside the box closes the search. A single cross in the field that
    /// closed the whole search would be the one control that does something other than what
    /// it looks like.
    private var field: some View {
        HStack(spacing: 6) {
            RPMSearchBox(text: $asked, prompt: Loc.get("Lookup_SearchButton"),
                         clearLabel: Loc.get("Lookup_ClearTooltip"), typing: $typing)

            // Outside the box, this closes the search. The magnifier key that opened the
            // search does the same thing, and both call `closeSearch`.
            Button {
                Haptics.pick()
                closeSearch()
            } label: {
                Text("\u{f00d}")
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
            }
            .buttonStyle(RPMGlassKey(edge: RPMSearchBox.height))
            .accessibilityLabel(Loc.get("Rpm_Cast_Close"))
        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // ── the header ──

    private var header: some View {
        VStack(alignment: .leading, spacing: PageTitle.subtitleGap) {
            // **The keys are drawn over the title's line and not in a row with it.** A
            // 48-point key is taller than the letters, and in a row it would set the
            // height of the line, so the counts below would sit as far down as the tallest
            // key and not as far down as the title.
            //
            // Thiamine draws its capitals at a quarter of the em, so 96 in
            // `RPMFont.header` gives a 24-point capital. Change that number, not the pages.
            //
            // The counts go under the whole row and not beside the keys, because the counts
            // of a shared wall also say whose records they are, and that line would be cut
            // off in the keys' column. It must stay on one line: a second line would push
            // the wall down.
            PageHeading(Loc.get("Settings_Library"), line: counts) { keys }
        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, 16)
        // **No top padding, and the Uno app has none either**, although its markup says
        // 10. `utu:SafeArea.Insets="Top"` REPLACES the padding on the side it is applied
        // to and does not add to it, so the 10 in the markup is ignored and its header
        // starts at the safe area. Adding 10 here would put the header 10 points lower than
        // the same screen in the Uno app.
        .padding(.bottom, 10)
    }

    /// The keys: search and sort.
    private var keys: some View {
        HStack(spacing: 0) {
            key(Glyph.search) {
                guard !searching else { closeSearch(); return }

                withAnimation(.easeOut(duration: 0.22)) { searching = true }
                typing = true
            }
            .accessibilityLabel(Loc.get("Lookup_SearchButton"))

            Menu {
                Picker(Loc.get("Rpm_Library_Sort"), selection: $order) {
                    Text(Loc.get("AlbumSort_Artist")).tag(AlbumOrdering.artist)
                    Text(Loc.get("AlbumSort_Album")).tag(AlbumOrdering.album)
                    Text(Loc.get("AlbumSort_Added")).tag(AlbumOrdering.added)
                    Text(Loc.get("AlbumSort_Year")).tag(AlbumOrdering.year)
                }
            } label: {
                glyph(Glyph.sort)
            }
            .accessibilityLabel(Loc.get("Rpm_Library_Sort"))
        }
        .rpmGlassGroup()
    }

    private func key(_ mark: String, _ press: @escaping () -> Void) -> some View {
        Button(action: press) { glyph(mark) }.buttonStyle(.plain)
    }

    private func glyph(_ mark: String) -> some View {
        Text(mark)
            .font(RPMFont.icon(16))
            .foregroundStyle(RPMInk.white(0xB8 / 255))
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private var counts: String {
        let records = albums.count == 1 ? Loc.get("Stats_AlbumsOne")
                                        : Loc.get("Stats_Albums", albums.count)
        let songs = albums.reduce(0) { $0 + $1.tracks.count }
        let tracks = songs == 1 ? Loc.get("Rpm_Profile_TracksOne") : Loc.get("Rpm_Queue_Count", songs)
        let held = Loc.get("Rpm_Library_CountsJoin", records, tracks)

        // The tab shows someone else's collection and nothing else on it says so. The
        // heading still reads Library and the covers look like the user's own.
        guard let lender, !lender.isEmpty else { return held }
        return Loc.get("Rpm_Library_SharedBy", lender) + "  \u{b7}  " + held
    }

    // ── the wall ──

    /// The wall in the chosen order. It is sorted once per library and per order, not once
    /// per evaluation of `body`. See ``SortedWall``.
    private var ordered: [CloudAlbum] { inOrder.wall(albums, in: order) }

    /// The wall, with pull to refresh, which reads the library again.
    ///
    /// **`refreshable` is on the wall and not on the page, and this matters.** It is passed
    /// down the environment and used by the nearest scroll view BELOW it. If it were on the
    /// page, the list of search results would also use it, and a pull there would re-read
    /// the library while the user is still typing a search.
    ///
    /// The empty state has no refresh. There is no scroll view to pull, and an empty library
    /// is fixed on a computer, not with a gesture.
    @ViewBuilder
    private var wall: some View {
        if albums.isEmpty {
            empty
        } else {
            records(ordered)
                .refreshable { await onRefresh() }
        }
    }

    @ViewBuilder
    private func records(_ ordered: [CloudAlbum]) -> some View {
        AlbumWall(albums: ordered, covers: covers,
                  targetStride: pinching ?? Self.bounded(stride),
                  onOpen: onOpen,
                  onPinch: { factor in
                      guard let factor else {
                          if let pinching { stride = pinching }
                          pinching = nil
                          return
                      }
                      pinching = Self.bounded(stride * factor)
                  })
    }

    /// Limits the card width to the range 60 to 900, whether it comes from a gesture or from
    /// the saved value. The limit stops a fast two-finger flick from asking for a very wide
    /// wall that then needs several pinches to undo, and stops a value saved by another build
    /// from opening the app on a wall of one card.
    private static func bounded(_ art: Double) -> Double { min(max(art, 60), 900) }

    /// **A collection that is known to be empty**, which is not the same as one that has not
    /// arrived yet. The sentence depends on whose collection it is: telling the user to
    /// upload their library from their computer, about a collection that belongs to someone
    /// else, gives an instruction they cannot follow.
    private var empty: some View {
        VStack(spacing: 10) {
            Text(Glyph.record)
                .font(RPMFont.icon(44))
                .foregroundStyle(RPMInk.white(0x3A / 255))

            Text(Loc.get(lender == nil ? "Rpm_Library_Empty" : "Rpm_Share_EmptyShelf"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The read is still in progress. It shows the turning record, the same as the Uno app
    /// and the same one this app opens with, because a wall that is still loading is not an
    /// empty wall.
    private var waiting: some View {
        VStack(spacing: 16) {
            RecordSpinner(diameter: 96)

            Text(Loc.get("Rpm_Library_Loading"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shows the error message and a retry button. A tab that fails silently leaves the user
    /// waiting with no information.
    private func failed(_ said: String) -> some View {
        VStack(spacing: 14) {
            Text(said)
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(Loc.get("Rpm_Library_Retry")) { Task { await onRefresh() } }
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 40,
                                            stretches: false, inset: 16, size: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── searching ──

    /// **Records first, then songs, shown as separate groups.** A typed name matches both
    /// the record with that name and every song on it. In one mixed list, the row the user
    /// wanted could be the fortieth, and a tap would be ambiguous: a record is opened and a
    /// song is played.
    @ViewBuilder
    private var results: some View {
        if records.isEmpty && found.isEmpty {
            // **Only once the search has caught up with the typing.** Showing "no
            // results" while the text is still changing would wrongly suggest that the
            // library does not hold what the next keystroke would find.
            if settled == asked {
                Text(Loc.get("Library_NoSearchResults"))
                    .font(RPMFont.display(14))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            DissolvingScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !records.isEmpty {
                        heading(Loc.get("Viz_BrowseAlbums"))

                        ForEach(records) { album in
                            Button { onOpen(album) } label: { record(album) }
                                .buttonStyle(RowPress())
                        }
                    }

                    if !found.isEmpty {
                        heading(Loc.get("Album_Tracks"))

                        ForEach(found) { hit in
                            Button { onPlay(hit.track) } label: { row(hit) }
                                .buttonStyle(RowPress())
                                .trackActions(hit.track, marked: isTrackMarked(hit.track),
                                              mine: isTrackMine(hit.track),
                                              upNext: upNext,
                                              onMark: onMarkTrack, onFile: onFile)
                        }
                    }

                    if found.count >= SongSearch.ceiling { cut }
                }
                .padding(.bottom, RPMLayout.foot)
            }
            .scrollIndicators(.hidden)
            // The keyboard covers the bottom of this list, so the last rows need room to
            // scroll into view. See ``PageFootRoom``.
            .keyboardRoom()
            // Dragging the list dismisses the keyboard, as every list under a search field
            // does on iOS.
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// A heading for one group of results. It uses the same kicker style as the counts line,
    /// so it looks like a label on the app's background and not like a row that can be
    /// tapped.
    private func heading(_ said: String) -> some View {
        Text(said)
            .rpmKicker()
            .textCase(.uppercase)
            .padding(.leading, RPMLayout.margin)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One record found. Tapping it opens the record, which is why it has its own kind of
    /// row.
    private func record(_ album: CloudAlbum) -> some View {
        HStack(spacing: 10) {
            // The same 3 points of empty space that song rows keep for the playing mark, so
            // both kinds of row start their sleeves on the same line.
            Color.clear.frame(width: 3, height: 26)

            SearchSleeve(album: album, covers: covers)
                .padding(.leading, 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(album.album)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(album.artist)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // A song row has nothing here. The track count shows that this row is a record
            // and not a song with a long title.
            Text(Loc.get("Rpm_Album_Tracks", album.tracks.count))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x66 / 255))
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(minHeight: 58)
    }

    /// Tells the user that the results were cut off at the limit. Without it, a list that
    /// stops at 300 would look like a library with only 300 songs.
    private var cut: some View {
        Text(Loc.get("Rpm_Library_SearchCeiling", SongSearch.ceiling))
            .font(RPMFont.display(12))
            .foregroundStyle(RPMInk.white(0x77 / 255))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
    }

    /// One song found. **The record is included in the hit** and not looked up here.
    /// Finding it per row would scan the whole library once per row, which costs most of a
    /// frame on any collection of real size. See ``SongSearch/SongHit``.
    private func row(_ hit: SongSearch.SongHit) -> some View {
        HStack(spacing: 10) {
            // The playing mark sits in the padding, so the sleeves start on the same line
            // as the header and the field above them.
            Rectangle()
                .fill(hit.track.rpmId == playing ? Color.white : .clear)
                .frame(width: 3, height: 26)
                .clipShape(Capsule())

            SearchSleeve(album: hit.album, covers: covers)
                .padding(.leading, 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(hit.track.title ?? "")
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(hit.track.artist ?? "")
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(minHeight: 58)
    }
}

/// The key of one search: the search text and the wall it searches in.
///
/// It has both, because either one can change while the other stays the same. Comparing it
/// is cheap: two Swift arrays that share a buffer are equal in constant time, and the view
/// receives a shared buffer on every evaluation while nothing has changed.
private struct Hunt: Equatable {
    let asked: String
    let wall: [CloudAlbum]
}

/// The 40-point sleeve of a search result.
private struct SearchSleeve: View {
    let album: CloudAlbum
    let covers: any CoverStore

    @State private var cover: Cover?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0x22 / 255))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                }

            if let cover {
                Sleeve(image: cover.image)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text(Glyph.record)
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: 40, height: 40)
        .task(id: album.key) {
            cover = nil
            cover = await covers.cover(for: album, edge: 40)
        }
    }
}

