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

    /// What else the search looks through: the artists, the genres and the playlists, so a name
    /// typed is found whichever view it lives in. See ``Findable``.
    private let findable: Findable
    private let onOpenArtist: (ArtistWallItem) -> Void
    private let onOpenGenre: (GenreWallItem) -> Void
    private let onOpenList: (PlaylistSet) -> Void

    /// The rest of the collection the search looks through, besides the records and their songs.
    public struct Findable: Equatable, Sendable {
        public let artists: [ArtistWallItem]
        public let genres: [GenreWallItem]
        public let playlists: [PlaylistSet]

        /// The records by key, for an artist found with no photograph: their row shows one of
        /// their own records, as their box on the artists wall stands on one. Not compared: it is
        /// read from the same records the wall is.
        public let albums: [String: CloudAlbum]

        public init(artists: [ArtistWallItem], genres: [GenreWallItem], playlists: [PlaylistSet],
                    albums: [String: CloudAlbum]) {
            self.artists = artists
            self.genres = genres
            self.playlists = playlists
            self.albums = albums
        }

        /// Nothing besides the records: a page built without the rest (a preview).
        public static let nothing = Findable(artists: [], genres: [], playlists: [], albums: [:])

        public static func == (a: Findable, b: Findable) -> Bool {
            a.artists == b.artists && a.genres == b.genres && a.playlists == b.playlists
        }
    }

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
                upNext: TrackActions.UpNext,
                found findable: Findable = .nothing,
                onOpenArtist: @escaping (ArtistWallItem) -> Void = { _ in },
                onOpenGenre: @escaping (GenreWallItem) -> Void = { _ in },
                onOpenList: @escaping (PlaylistSet) -> Void = { _ in }) {
        self.findable = findable
        self.onOpenArtist = onOpenArtist
        self.onOpenGenre = onOpenGenre
        self.onOpenList = onOpenList
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

    /// The artists, genres and playlists the same words found. See ``CollectionSearch``.
    @State private var artists: [ArtistWallItem] = []
    @State private var genres: [GenreWallItem] = []
    @State private var lists: [PlaylistSet] = []

    /// The groups of results that show all their answers, by name. Every new answer starts them
    /// folded. See ``group(_:_:_:row:)``.
    @State private var unfolded: Set<String> = []

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
                // While the search is open the heading and the views fade away, and the field rises
                // into their place. They come back only when the search is closed with its cross.
                VStack(spacing: 0) {
                    if !searching { header.transition(.opacity) }
                    if searching { field }
                    if !searching { LibraryModeTabs($mode).transition(.opacity) }
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
        .task(id: Hunt(asked: asked, wall: ordered, rest: findable)) {
            let asking = asked

            guard !asking.trimmingCharacters(in: .whitespaces).isEmpty else {
                found = []
                records = []
                artists = []
                genres = []
                lists = []
                unfolded = []
                settled = asking
                return
            }

            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }

            let library = ordered
            let rest = findable
            let began = Date()
            let hits = await Self.look(through: library, and: rest, for: asking)

            guard !Task.isCancelled else { return }

            MainActorWatch.searched(albums: library.count, hits: hits.songs.count,
                                    records: hits.records.count,
                                    took: Date().timeIntervalSince(began),
                                    sorts: inOrder.sorts)

            records = hits.records
            found = hits.songs
            artists = hits.artists
            genres = hits.genres
            lists = hits.lists
            unfolded = []
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
    ///
    /// The artists, genres and playlists are searched in the same hop, for the same reason.
    private nonisolated static func look(
        through library: [CloudAlbum], and rest: Findable, for asking: String
    ) async -> Hits {
        Hits(records: SongSearch.records(library, for: asking),
             songs: SongSearch.through(library, for: asking),
             artists: CollectionSearch.artists(rest.artists, for: asking),
             genres: CollectionSearch.genres(rest.genres, for: asking),
             lists: CollectionSearch.playlists(rest.playlists, for: asking))
    }

    /// What one search found.
    private struct Hits: Sendable {
        let records: [CloudAlbum]
        let songs: [SongSearch.SongHit]
        let artists: [ArtistWallItem]
        let genres: [GenreWallItem]
        let lists: [PlaylistSet]
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
        records = []
        artists = []
        genres = []
        lists = []
        unfolded = []
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

    /// Whether the search found nothing at all.
    private var foundNothing: Bool {
        records.isEmpty && found.isEmpty && artists.isEmpty && genres.isEmpty && lists.isEmpty
    }

    /// **Everything the collection holds that the words name, whichever view it lives in, each
    /// kind under its own heading**: artists, records, songs, playlists, genres. A typed name
    /// matches both the record with that name and every song on it. In one mixed list, the row
    /// the user wanted could be the fortieth, and a tap would be ambiguous: a record is opened and
    /// a song is played.
    ///
    /// **A group shows its first ``firstShown`` answers.** One with more has View more at the right
    /// of its heading, which shows the rest, and then View less. The rest come in as the Wikipedia
    /// text unfolds on the record and artist pages: they fade in while everything under them moves
    /// down to make room, in the same time (``unfoldTime``). A new search starts every group folded.
    @ViewBuilder
    private var results: some View {
        if foundNothing {
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
                    group("artists", Loc.get("Artists_Title"), artists) { artist in
                        Button { onOpenArtist(artist) } label: { artistRow(artist) }
                            .buttonStyle(RowPress())
                    }

                    group("records", Loc.get("Viz_BrowseAlbums"), records) { album in
                        Button { onOpen(album) } label: { record(album) }
                            .buttonStyle(RowPress())
                    }

                    group("songs", Loc.get("Album_Tracks"), found) { hit in
                        Button { onPlay(hit.track) } label: { row(hit) }
                            .buttonStyle(RowPress())
                            .trackActions(hit.track, marked: isTrackMarked(hit.track),
                                          mine: isTrackMine(hit.track),
                                          upNext: upNext,
                                          onMark: onMarkTrack, onFile: onFile)
                    }

                    if found.count >= SongSearch.ceiling && unfolded.contains("songs") {
                        cut.transition(.opacity)
                    }

                    group("playlists", Loc.get("Playlists_Title"), lists) { list in
                        Button { onOpenList(list) } label: { listRow(list) }
                            .buttonStyle(RowPress())
                    }

                    group("genres", Loc.get("Genres_Title"), genres) { genre in
                        Button { onOpenGenre(genre) } label: { genreRow(genre) }
                            .buttonStyle(RowPress())
                    }
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

    /// How many answers a group shows before View more.
    private static let firstShown = 5

    /// How long a group takes to unfold or fold: the Wikipedia text's time on the record and
    /// artist pages.
    private static let unfoldTime: Double = 0.32

    /// One group of answers: its heading, its first ``firstShown`` rows, and the rest while it is
    /// open. Nothing at all for a kind with no answers. The rows past the first fade in and out,
    /// and the rows and groups under them move in the same time, so the group seems to open
    /// downward from its last row.
    @ViewBuilder
    private func group<Answer: Identifiable, Row: View>(
        _ id: String, _ title: String, _ answers: [Answer],
        @ViewBuilder row: @escaping (Answer) -> Row
    ) -> some View {
        if !answers.isEmpty {
            let open = unfolded.contains(id)
            let folds = answers.count > Self.firstShown

            heading(title, toggle: folds ? Loc.get(open ? "Library_SearchViewLess"
                                                        : "Library_SearchViewMore") : nil) {
                withAnimation(.easeInOut(duration: Self.unfoldTime)) {
                    if open { unfolded.remove(id) } else { unfolded.insert(id) }
                }
            }

            ForEach(open || !folds ? answers : Array(answers.prefix(Self.firstShown))) { answer in
                row(answer).transition(.opacity)
            }
        }
    }

    /// A heading for one group of results. It uses the same kicker style as the counts line,
    /// so it looks like a label on the app's background and not like a row that can be
    /// tapped. `toggle` is the words of the key at its right that shows the rest of the group or
    /// folds it again; nil for a group that shows all it has.
    private func heading(_ said: String, toggle: String? = nil,
                         onToggle: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 8) {
            Text(said)
                .rpmKicker()
                .textCase(.uppercase)

            Spacer(minLength: 0)

            if let toggle {
                Button {
                    Haptics.pick()
                    onToggle()
                } label: {
                    Text(toggle)
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0xCC / 255))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, RPMLayout.margin)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The shape every row of the results shares: the playing mark in the margin, a 40-point
    /// picture, two lines, and whatever goes at the end.
    private func entry<Picture: View, End: View>(
        _ title: String, _ line: String, playing: Bool = false,
        @ViewBuilder picture: () -> Picture,
        @ViewBuilder end: () -> End
    ) -> some View {
        HStack(spacing: 10) {
            // The playing mark sits in the padding, so the pictures start on the same line as
            // the header and the field above them.
            Rectangle()
                .fill(playing ? Color.white : .clear)
                .frame(width: 3, height: 26)
                .clipShape(Capsule())

            picture()
                .padding(.leading, 9)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(line)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            end()
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    /// A row with nothing at its end.
    private func entry<Picture: View>(
        _ title: String, _ line: String, playing: Bool = false,
        @ViewBuilder picture: () -> Picture
    ) -> some View {
        entry(title, line, playing: playing, picture: picture) { EmptyView() }
    }

    /// An artist found: their photograph where there is one, in a circle, their name, and how many
    /// records of theirs are here. Round, so an artist reads apart from the records, playlists and
    /// genres around them, which are square.
    private func artistRow(_ artist: ArtistWallItem) -> some View {
        entry(artist.name, Self.albumCount(artist.own.count)) {
            SearchFace(artist: artist,
                       first: artist.own.lazy.compactMap { findable.albums[$0] }.first,
                       covers: covers)
        }
    }

    /// A playlist found: its square, its name, and how many songs it holds.
    private func listRow(_ list: PlaylistSet) -> some View {
        entry(list.name, Loc.get("Home_Songs", list.tracks.count)) {
            PlaylistSleeve(list: list.picture, track: list.tracks.first, glyph: Glyph.playlists,
                           edge: 40, corner: 6, mark: 15, covers: covers,
                           framed: FramedList.of(list))
        }
    }

    /// A genre found: its photograph, its name, and how many records it holds.
    private func genreRow(_ genre: GenreWallItem) -> some View {
        entry(genre.name, Self.albumCount(genre.albums.count)) {
            GenrePicture(genre: genre.name)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private static func albumCount(_ count: Int) -> String {
        count == 1 ? Loc.get("Stats_AlbumsOne") : Loc.get("Stats_Albums", count)
    }

    /// One record found. Tapping it opens the record, which is why it has its own kind of
    /// row: a song row has nothing at its end, and the track count shows that this row is a
    /// record and not a song with a long title.
    private func record(_ album: CloudAlbum) -> some View {
        entry(album.album, album.artist) {
            SearchSleeve(album: album, covers: covers)
        } end: {
            Text(Loc.get("Rpm_Album_Tracks", album.tracks.count))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x66 / 255))
                .lineLimit(1)
        }
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
        entry(hit.track.title ?? "", hit.track.artist ?? "", playing: hit.track.rpmId == playing) {
            SearchSleeve(album: hit.album, covers: covers)
        }
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

    /// The artists, genres and playlists searched as well: a list that arrives during a search is
    /// searched again.
    let rest: LibraryPage.Findable
}

/// The 40-point circle of an artist found: their photograph, or one of their own records where
/// there is none, or their mark.
private struct SearchFace: View {
    let artist: ArtistWallItem
    let first: CloudAlbum?
    let covers: any CoverStore

    @State private var picture: Cover?

    init(artist: ArtistWallItem, first: CloudAlbum?, covers: any CoverStore) {
        self.artist = artist
        self.first = first
        self.covers = covers
        // What the store already holds, so a row shown again has its picture from the first frame.
        _picture = State(initialValue: covers.portraitHeld(of: artist.name, edge: 40)
                         ?? first.flatMap { covers.coverHeld(for: $0, edge: 40) })
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0x22 / 255))

            if let picture {
                Color.clear
                    .overlay {
                        picture.image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipShape(Circle())
                    .transition(.opacity)
            } else {
                ArtistMark.key(15)
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: 40, height: 40)
        .animation(.easeOut(duration: 0.2), value: picture != nil)
        .task(id: artist.name) {
            if let found = await covers.portrait(of: artist.name, edge: 40) {
                picture = found
            } else if let first, let sleeve = await covers.cover(for: first, edge: 40) {
                picture = sleeve
            }
        }
    }
}

/// The 40-point sleeve of a search result.
private struct SearchSleeve: View {
    let album: CloudAlbum
    let covers: any CoverStore

    @State private var cover: Cover?

    init(album: CloudAlbum, covers: any CoverStore) {
        self.album = album
        self.covers = covers
        // What the store already holds, so a row shown again has its sleeve from the first frame.
        _cover = State(initialValue: covers.coverHeld(for: album, edge: 40))
    }

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
            cover = covers.coverHeld(for: album, edge: 40)
            if let fetched = await covers.cover(for: album, edge: 40) { cover = fetched }
        }
    }
}

