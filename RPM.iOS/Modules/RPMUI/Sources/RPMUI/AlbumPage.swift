import SwiftUI
import RPMKit
import RPMLibrary
import RPMAudio
import RPMDesign

/// One record.
///
/// The page is its own ground: the sleeve, blurred until it is only colour, so the
/// record's own colours spread across the page. That is what makes each album page look
/// different, and it is the reason this app has no accent colour of its own.
public struct AlbumPage: View {
    private let album: CloudAlbum
    private let covers: any CoverStore
    private let marked: Bool

    /// Whether the record's owner marked it classical, which draws the tracklist as
    /// works with their movements under them. **No default**: a record is classical
    /// because somebody said so, and a page built without the answer would draw
    /// every classical record as forty rows called "Allegro" without saying why.
    private let classical: Bool

    /// Where the Wikipedia text under the keys comes from. See ``AboutText``.
    private let articles: ArticleStore

    /// Which row the speaker is on, if it is on one of these. The mark is out in the
    /// list's left margin rather than in the row, because a marker in the flow pushes
    /// every number and title right of everything in the header.
    private let playing: String?

    private let onPlay: (Int, Tapped) -> Void
    private let onShuffle: () -> Void
    private let onMark: (Bool) -> Void
    private let onBack: () -> Void

    /// Whether one SONG is loved, which is not the same question as whether the
    /// record is. Asked per row rather than handed over as a set: the answer changes
    /// under an open page when somebody loves what is playing.
    private let isTrackMarked: (CloudTrack) -> Bool

    /// Whether a song is on this account's own shelf.
    ///
    /// **No default, unlike the mark beside it.** A borrowed song can be neither
    /// marked nor filed. The mark would be stored against an id this account does not
    /// own, and a playlist names songs by id, so a song from somebody else's collection
    /// resolves to nothing here. This one answer decides whether those actions are
    /// offered, and a default would let a page be built without it.
    private let isTrackMine: (CloudTrack) -> Bool
    private let onMarkTrack: (CloudTrack, Bool) -> Void
    private let onFile: (CloudTrack) -> Void

    /// What hearing a song after this one means on these rows. See
    /// ``TrackActions/UpNext``.
    private let upNext: TrackActions.UpNext

    /// What everybody else made of the record, under its tracks.
    ///
    /// Handed in rather than built here: it is a whole feature of its own with its
    /// own state, and the album page's job is the record. Type-erased rather than generic,
    /// because a generic page cannot hold the two static constants it is laid out from.
    private let wall: AnyView?

    /// What the wall makes of this record, for the line under the format. Nil until
    /// RPM answers: **a page whose reviews never load is an album page, not an error
    /// page**, so the line is absent rather than empty.
    private let rating: (average: Double, count: Int)?

    /// The download key, or nil where there is none to offer: a borrowed shelf.
    private let download: DownloadKey?

    /// Whether a song can be played now. **No default**: offline, it is what greys the
    /// songs that are not on the phone, and a page built without it offers every song and
    /// plays none of them.
    private let canPlay: (CloudTrack) -> Bool

    /// The collection on screen, which the Similar albums row is picked from, and what pressing
    /// a record in that row does. **No defaults**: a page built without them has no row, and
    /// nothing would say so.
    private let shelf: [CloudAlbum]
    private let onOpenAlbum: (CloudAlbum) -> Void

    /// The artist pages the artist line opens, in credit order, and what opening one does.
    /// **No defaults**: a page built without them has an artist line that does nothing when
    /// pressed. Empty leaves the line as plain text. See ``ReadArtists/artists(of:in:)``.
    private let artists: [ArtistWallItem]
    private let onArtist: (ArtistWallItem) -> Void

    /// The Similar albums row, and the record it was worked out for. Drawn only while that is
    /// the record on this page; see ``similarRow``.
    @State private var similar: (key: String, row: [CloudAlbum])?

    @State private var cover: Cover?

    /// The Wikipedia text, and the record it was read for. Filled from the store's cache when the
    /// page is built, so a record opened before has its text on the first frame.
    @State private var about: AboutRead

    /// The text in the sheet, while it is up.
    @State private var reading: AboutReading?

    public init(album: CloudAlbum, covers: any CoverStore, articles: ArticleStore, marked: Bool,
                classical: Bool, download: DownloadKey?, canPlay: @escaping (CloudTrack) -> Bool,
                shelf: [CloudAlbum], onOpenAlbum: @escaping (CloudAlbum) -> Void,
                artists: [ArtistWallItem], onArtist: @escaping (ArtistWallItem) -> Void,
                playing: String? = nil,
                onPlay: @escaping (Int, Tapped) -> Void, onShuffle: @escaping () -> Void,
                onMark: @escaping (Bool) -> Void, onBack: @escaping () -> Void,
                isTrackMarked: @escaping (CloudTrack) -> Bool = { _ in false },
                isTrackMine: @escaping (CloudTrack) -> Bool,
                onMarkTrack: @escaping (CloudTrack, Bool) -> Void = { _, _ in },
                onFile: @escaping (CloudTrack) -> Void = { _ in },
                upNext: TrackActions.UpNext,
                wall: AnyView? = nil,
                rating: (average: Double, count: Int)? = nil) {
        self.wall = wall
        self.rating = rating
        self.download = download
        self.canPlay = canPlay
        self.shelf = shelf
        self.onOpenAlbum = onOpenAlbum
        self.artists = artists
        self.onArtist = onArtist
        self.album = album
        self.covers = covers
        self.articles = articles
        self._about = State(initialValue: AboutRead(Self.subject(of: album), in: articles))
        self.marked = marked
        self.classical = classical
        self.playing = playing
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.onMark = onMark
        self.onBack = onBack
        self.isTrackMarked = isTrackMarked
        self.isTrackMine = isTrackMine
        self.onMarkTrack = onMarkTrack
        self.onFile = onFile
        self.upNext = upNext
    }

    private static let coverFraction: CGFloat = 0.62

    /// How wide the page is, for the one thing that needs it.
    ///
    /// A preference rather than a `GeometryReader` wrapped round the whole page.
    /// Wrapping a scrolling page in one puts its rows in a coordinate space of its
    /// own, and that space does not always agree with the one taps are resolved in: the
    /// list draws in the right place but answers a touch one row further down. The width
    /// is measured from the background, where it does not change the layout.
    private struct PageWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @State private var width: CGFloat = 0

    /// **A `List`, but it draws nothing a list normally draws.**
    ///
    /// A `ScrollView` round a `LazyVStack` would suit a page made of a header, some songs
    /// and a wall of reviews. It cannot have the left swipe, though: `swipeActions` works
    /// only in a `List` and is silently ignored anywhere else, and the two keys in
    /// ``TrackActions`` depend on it. Every row here is `plainRow()` (no fill, no inset,
    /// no separator), so the page looks like a plain stack.
    public var body: some View {
        List {
            Group {
                header(edge: coverEdge).scrollProbe()
                tracks
                similarRow
                wall

                // The clearance belongs to whatever is actually last on the page, not
                // to the list's own padding.
                Color.clear.frame(height: 40)
            }
            .plainRow()
        }
        .listStyle(.plain)
        // The rows are laid out at this list's width and not at the cell's,
        // so a swipe moves them instead of squeezing them. See
        // ``View/rowsKeepTheirWidth()``.
        .rowsKeepTheirWidth()
        .scrollContentBackground(.hidden)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PageWidth.self, value: geometry.size.width)
            }
        }
        // The rows size themselves. A list's own minimum row height would give a song's
        // row and a disc's heading the same forty-four points.
        .environment(\.defaultMinListRowHeight, 1)
        .scrollIndicators(.hidden)
        // The list runs up behind the status bar, and what scrolls up behind the clock and the
        // back key dissolves into the page's background there, as on home. Before the ground
        // and the back key, so the mask takes the list and nothing laid over it, and the back
        // key keeps the safe area.
        .ignoresSafeArea(edges: .top)
        .dissolvesAtTop(under: RPMSafeArea.top + RPMLayout.backRow)
        .onPreferenceChange(PageWidth.self) { width = $0 }
        // Behind and in front, rather than as siblings in a stack. A background and
        // an overlay are sized to the view they belong to and take no part in its
        // layout, so the page keeps the geometry it would have had on its own.
        .background { ground }
        .rpmFloatingBack(RPMBackKey(label: Loc.get("Album_Back"), action: onBack))
        .task(id: album.key) { cover = await covers.cover(for: album, edge: coverEdge) }
        .task(id: subject.id) { await AboutRead.read(subject, from: articles, into: $about) }
        .task(id: SimilarAsk(album: album.key, shelf: shelf.count)) { await readSimilar() }
        .aboutSheet($reading)
    }

    /// What the Wikipedia text is about: the record, named as the desktop's album page names it.
    private var subject: ArticleStore.Subject { Self.subject(of: album) }

    private static func subject(of album: CloudAlbum) -> ArticleStore.Subject {
        .album(artist: album.artist, title: album.album, tracks: album.tracks.count)
    }

    /// How much of the screen the sleeve takes. Six tenths leaves the title, the
    /// count and the keys visible without scrolling on the smallest phone this runs on.
    private var coverEdge: CGFloat {
        min(max((width > 0 ? width : 390) * Self.coverFraction, 160), 360).rounded()
    }

    // ── the ground ──

    /// The sleeve blurred under the whole page, over the app's own grooves. The layers
    /// and the veil are ``ArtGround``'s, which every page that dresses itself stands on.
    private var ground: some View {
        ArtGround(picture: cover?.image, accent: cover?.accent, showing: album.key)
    }

    // ── the record ──

    private func header(edge: CGFloat) -> some View {
        VStack(spacing: 12) {
            // Room for the status bar and the back key, which floats rather than scrolling
            // with the page. The list starts at the top of the screen.
            Color.clear.frame(height: RPMSafeArea.top + RPMLayout.backRow)

            sleeve(edge: edge)

            VStack(spacing: 4) {
                Text(album.album)
                    .font(RPMFont.displayBold(24))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                artistLine
            }
            .padding(.top, 10)

            // How much record there is, and what it is made of. The count is a chip
            // because it describes the record above it. The format sits under it,
            // quieter, because it describes the file and not the music.
            VStack(spacing: 4) {
                Text(count)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0xE6 / 255))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(RPMInk.white(0x1F / 255)))

                if !format.isEmpty {
                    Text(format)
                        .font(RPMFont.display(12).italic())
                        .foregroundStyle(RPMInk.white(0x8A / 255))
                }
            }

            if let rating, rating.count > 0 {
                HStack(spacing: 8) {
                    StarRating(rating.average, size: 13)

                    Text(rating.count == 1 ? Loc.get("Rpm_Album_RatingsOne")
                                           : Loc.get("Rpm_Album_Ratings", rating.count))
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0xAA / 255))
                }
            }

            // What Wikipedia says about the record, where it says anything. Above the keys, so
            // it is read before the record is played. Text that arrives from the network moves
            // the keys and the songs down in one step, and nothing else moves: the row grows,
            // and a row that grows is not animated (see AboutRead). The text fades in.
            if let article = about.article(for: subject) {
                AboutText(article: article) {
                    reading = AboutReading(heading: Loc.get("TrackInfo_AboutAlbum"),
                                           name: album.album, article: article)
                }
                .padding(.top, 4)
            }

            keys

            // Only while it is true. The page says so plainly: the list is then in the
            // order the server returned, and it is not shown as the running order.
            if !album.isOrdered {
                Text(Loc.get("Rpm_Album_Unordered"))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x77 / 255))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, RPMLayout.margin)
        .padding(.bottom, 14)
    }

    /// The record's artist. Pressing it opens their page; on a record two acts made, it
    /// opens a menu with both.
    ///
    /// `.plain` on the button, because a button with the default style inside a `List`
    /// row takes taps on the whole row, and this row also holds the play keys.
    @ViewBuilder
    private var artistLine: some View {
        let name = Text(album.artist)
            .font(RPMFont.display(16))
            .foregroundStyle(RPMInk.white(0xD9 / 255))
            .lineLimit(1)

        switch artists.count {
        case 0:
            name

        case 1:
            Button { onArtist(artists[0]) } label: { name }
                .buttonStyle(.plain)

        default:
            Menu {
                ForEach(artists) { who in
                    Button(who.name) { onArtist(who) }
                }
            } label: {
                name
            }
        }
    }

    /// The sleeve, square and centred, filling the whole square with no mount around it.
    private func sleeve(edge: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0x22 / 255))

            if let cover {
                Sleeve(image: cover.image)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Text(Glyph.record)
                    .font(RPMFont.icon(52))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: edge, height: edge)
    }

    /// Play, the same record in another order, and the mark on it.
    ///
    /// Shuffle is beside the play key rather than in a menu, because it is the second
    /// thing anybody does to an album.
    private var keys: some View {
        HStack(spacing: 10) {
            Button { onPlay(0, .list) } label: {
                HStack(spacing: 10) {
                    Text(Glyph.play).font(RPMFont.icon(15))
                    Text(Loc.get("AlbumGrid_PlayAll")).font(RPMFont.display(17))
                }
            }
            .buttonStyle(RPMGlassButton(.primary, radius: 14, height: 50))
            .disabled(!anyPlayable)
            .opacity(anyPlayable ? 1 : 0.4)

            Button(action: onShuffle) {
                Text(Glyph.shuffle).font(RPMFont.icon(17))
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 14, height: 50))
            .frame(width: 56)
            .accessibilityLabel(Loc.get("AlbumMenu_Shuffle"))
            .disabled(!anyPlayable)
            .opacity(anyPlayable ? 1 : 0.4)

            // The mark on the **record**, which is not the same thing as a mark on
            // its songs. It goes to the shared wall, so an album loved on the phone is
            // loved on the computer.
            Button { onMark(!marked) } label: {
                Text(Glyph.heart)
                    .font(marked ? RPMFont.icon(17) : RPMFont.iconOutline(17))
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 14, height: 50))
            .frame(width: 56)
            .accessibilityLabel(marked ? Loc.get("Album_UnsetFavorite") : Loc.get("Album_SetFavorite"))

            if let download { DownloadButton(key: download) }
        }
        .padding(.top, 6)
    }

    /// Whether anything on this record can be played now. Offline and with nothing on the
    /// phone, the play and shuffle keys are dimmed.
    private var anyPlayable: Bool { album.tracks.contains(where: canPlay) }

    // ── similar albums ──

    /// What the Similar albums row is worked out again for: another record, or a collection with
    /// records added or gone. **Not** a collection whose tags changed and whose size did not;
    /// the row keeps the old answer until the page is opened again.
    private struct SimilarAsk: Hashable {
        let album: String
        let shelf: Int
    }

    /// Other records on this collection to play after this one, under the songs: the desktop's
    /// row, drawn as the home screen's rows are. Nothing at all where there are none.
    @ViewBuilder
    private var similarRow: some View {
        if let similar, similar.key == album.key, !similar.row.isEmpty {
            HomeRowView(heading: Loc.get("Album_SimilarAlbums"), albums: similar.row,
                        covers: covers, onOpen: onOpenAlbum)
                .padding(.top, 28)
        }
    }

    /// Ranks the collection off the main actor: it walks every track on it.
    private func readSimilar() async {
        let album = album
        let shelf = shelf
        let row = await Task.detached(priority: .utility) {
            SimilarAlbums.row(for: album, on: shelf)
        }.value

        // The page moved to another record, or the collection changed, while this was working.
        // The newer ask writes its own answer.
        guard !Task.isCancelled else { return }
        similar = (album.key, row)
    }

    // ── the songs ──

    @ViewBuilder
    private var tracks: some View {
        ForEach(AlbumLines.build(album.tracks, classical: classical)) { line in
            switch line {
            case .disc(let number):
                // Only on a set. A single-disc album never draws one, so it is a plain
                // track list.
                VStack(alignment: .leading, spacing: 6) {
                    Text(Loc.get("AlbumEdit_DiscN", number)).rpmKicker()
                    Rectangle().fill(RPMInk.white(0x1F / 255)).frame(height: 1)
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.top, 12)
                .padding(.bottom, 2)

            case .work(let heading):
                workHeading(heading)

            case .song(let song):
                // A button rather than a tap gesture on a shape. A row that starts a
                // song is a control, and the framework's own hit testing for a button
                // must be used: a gesture attached to a rectangle inside a lazy stack
                // can send a tap to the wrong line.
                let track = song.track
                Button {
                    if let at = album.tracks.firstIndex(where: { $0.rpmId == track.rpmId }) {
                        onPlay(at, .song)
                    }
                } label: {
                    row(song)
                }
                .buttonStyle(RowPress())
                // Offline, a song with no copy on the phone is shown and not offered.
                .disabled(!canPlay(track))
                .opacity(canPlay(track) ? 1 : 0.35)
                .trackActions(track, marked: isTrackMarked(track), mine: isTrackMine(track),
                              upNext: upNext, onMark: onMarkTrack, onFile: onFile)
            }
        }
    }

    /// How far a movement is set in from the work above it. The desktop's 18.
    private static let movementIndent: CGFloat = 18

    /// Where a line's number starts: the row's own inset, the playing mark, and the
    /// gap after it. A work heading starts here too, so a piece's number and a
    /// heading's first letter are on one vertical and only movements are set in.
    private static let numberEdge: CGFloat = 8 + 3 + 14

    /// The line that opens a work: its name, who wrote it, and how long the whole
    /// piece runs. Not a control: nothing plays from it, as on the desktop.
    private func workHeading(_ heading: AlbumWorkHeading) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(heading.title)
                    .font(RPMFont.displayBold(16))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let composer = heading.composer {
                    Text(composer)
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(length(heading.duration))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
        .padding(.leading, Self.numberEdge)
        .padding(.trailing, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .keepsItsWidth()
    }

    private func row(_ song: AlbumSongLine) -> some View {
        let track = song.track

        return HStack(spacing: 14) {
            // The playing mark, out in the margin: three points of white, which is
            // what "playing" looks like everywhere in this app. Never indented with a
            // movement, so it stays in the margin on every line.
            Rectangle()
                .fill(track.rpmId == playing ? Color.white : .clear)
                .frame(width: 3, height: 28)
                .clipShape(Capsule())
            // Blank, not a dash, on a row the catalogue has not reached: a column of
            // dashes looks like data. Left-aligned in a fixed column, so a single digit
            // is not set in from the line everything else is flush with.
            Text(number(of: track))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x66 / 255))
                .frame(width: 22, alignment: .leading)
                .padding(.leading, song.level == .movement ? Self.movementIndent : 0)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // A piece is set in the heading's weight: on a classical record the
                    // top level of the listing reads as one level, heading or piece.
                    Text(song.title)
                        .font(song.level == .piece ? RPMFont.displayBold(16) : RPMFont.display(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // The E after the title rather than before it, and in the flow so
                    // a long title is trimmed to make room for it instead of running
                    // underneath it.
                    if track.isExplicit {
                        Text("E")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RPMInk.ground)
                            .frame(width: 14, height: 14)
                            .background(RoundedRectangle(cornerRadius: 3).fill(RPMInk.white(0xAA / 255)))
                    }
                }

                // The track's own artist, which on a compilation is not the album's.
                //
                // On EVERY row, as on the desktop, not only where it differs from the
                // record's. A line that appears on some rows and not on others makes
                // rows of two heights.
                //
                // On a classical record the line is the desktop's instead: the
                // composer under a piece, and nothing under a movement, whose work
                // heading has already said who wrote it.
                if let second = secondLine(song) {
                    Text(second)
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(length(track.duration))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
        .padding(.leading, 8)
        .padding(.trailing, 20)
        .frame(minHeight: 56)
        // A swipe narrows the cell; this row is not narrowed with it. See
        // ``View/keepsItsWidth()``.
        .keepsItsWidth()
    }

    /// What the small line under a song's title says. See ``row(_:)``.
    private func secondLine(_ song: AlbumSongLine) -> String? {
        switch song.level {
        case .plain:
            guard let artist = song.track.artist, !artist.isEmpty else { return nil }
            return artist
        case .piece, .movement:
            return song.subtitle
        }
    }

    // ── the words ──

    private var count: String {
        let songs = album.tracks.count == 1
            ? Loc.get("Rpm_Album_TracksOne")
            : Loc.get("Rpm_Album_Tracks", album.tracks.count)
        guard album.duration > .zero else { return songs }
        return "\(songs) · \(Self.runtime(album.duration))"
    }

    /// The album's first track answers for the record. A set ripped at two
    /// resolutions is described by its opener, which is what a sleeve does too.
    private var format: String {
        (album.tracks.compactMap(\.tags).first { $0.hasFormat }?.format ?? []).joined(separator: "  ·  ")
    }

    private func number(of track: CloudTrack) -> String {
        let at = AlbumGrouping.track(of: track)
        return at > 0 ? "\(at)" : ""
    }

    static func runtime(_ total: Duration) -> String {
        let seconds = Int(total.components.seconds)
        let hours = seconds / 3600
        return hours >= 1 ? Loc.get("Stats_HoursMinutes", hours, (seconds % 3600) / 60)
                          : Loc.get("Stats_Minutes", seconds / 60)
    }

    static func length(_ total: Duration) -> String {
        let seconds = Int(total.components.seconds)
        guard seconds > 0 else { return "" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func length(_ total: Duration) -> String { Self.length(total) }
}


/// A row lights when it is picked, and nothing else lights with it. The stock button
/// style fades the whole line, which on a list of songs looks as if the row is going away.
///
/// Shared by every list of rows in the app, so a row answers a finger the same way
/// wherever it is.
///
/// **Starting a track is not immediate, so the row has to show a response.** A tap goes
/// through a claim on the audio session and a signature from the store before anything
/// can begin, which on a cold app takes most of a second. The row therefore gives
/// feedback that can be seen from under a thumb (a lit row) and felt (a tap through the
/// case of the phone). See ``Haptics``.
///
/// **The press is not the trigger, because inside a `List` there may not be one.**
/// Every page of rows here is a `List`, and a list's scroll view holds touches back so it
/// can tell a tap from the start of a scroll. A finger that lifts before that delay ends
/// gets its down and its up delivered together, in one turn of the run loop: `isPressed`
/// goes true and false between two frames, so a mark drawn from it is never painted, and
/// a timer started by it never runs. A held finger would light the row, but a tap would
/// not, and a tap is how a list is normally used.
///
/// So the mark is driven by the **action**, which every tap is guaranteed to reach (the
/// row plays the song, so the action runs). `PrimitiveButtonStyle` makes that possible:
/// it is handed `trigger()` rather than a press, and the ordinary `Button` that wraps the
/// row keeps the framework's own hit testing, scrolling and context menu. The press still
/// lights the row when it does arrive (under a held finger the mark appears before the
/// action does). Whichever of the two comes first lights the row. The second finds it
/// already lit and only restarts the timer that puts it out.
struct RowPress: PrimitiveButtonStyle {
    /// How long the mark stays after the finger has gone, and how long it then takes
    /// to fade. Short enough that a row is not still lit when the next screen arrives,
    /// long enough to be seen by a person whose thumb was covering the row.
    fileprivate static let hold = Duration.milliseconds(140)
    fileprivate static let fade = 0.25

    /// How long a finger has to stay put before the row lights.
    ///
    /// **A sideways pull must never light a row.** The press begins the moment a finger
    /// lands and is cancelled a moment later when the gesture turns out to be a swipe. With
    /// no delay, that is long enough to paint the mark across the row and then remove it
    /// as the row opens, so a pull to the right would look like the highlight shrinking in
    /// from the right.
    ///
    /// A tap is lit by the tap itself and not by this timer, so taps are not slowed. This
    /// is only the wait before a finger that has not yet shown what it is doing is treated
    /// as a press. It matches `UIScrollView`'s own delay.
    fileprivate static let settle = Duration.milliseconds(150)

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    /// A view, not the style's own body, because the mark is state: the style is
    /// handed a press that can last less than a frame and has to remember it for longer.
    private struct Row: View {
        let configuration: Configuration

        @State private var lit = false

        /// The timer that will put it out, held so a second pick can cancel it: a
        /// row picked again while it is fading must light, not keep fading.
        @State private var release: Task<Void, Never>?

        /// The timer that will light it, held so a finger that leaves (or turns into
        /// a swipe) can cancel it before anything is drawn. See ``RowPress/settle``.
        @State private var lighting: Task<Void, Never>?

        var body: some View {
            Button {
                light()
                unlight()
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(Mark(lit: lit, down: whenItSettles, up: unlight))
            // A row that scrolls away mid-fade cancels its timers: the view is
            // reused for another song, and that one must not inherit a mark.
            .onDisappear {
                lighting?.cancel()
                lighting = nil
                release?.cancel()
                release = nil
                lit = false
            }
        }

        /// A finger has landed. Light the row **if the finger is still there after a short
        /// wait**, which is what tells a press apart from the beginning of a swipe.
        private func whenItSettles() {
            guard !lit else { light(); return }

            lighting?.cancel()
            lighting = Task { @MainActor in
                try? await Task.sleep(for: RowPress.settle)
                guard !Task.isCancelled else { return }
                light()
            }
        }

        /// Light it, and stop anything that was going to put it out. Silent if it is
        /// already lit: the press and the action are two halves of one tap, and the
        /// hand should feel one tick, not two.
        private func light() {
            release?.cancel()
            release = nil
            guard !lit else { return }
            lit = true
            Haptics.pick()
        }

        /// Starts the timer that puts the mark out. It does not run on the way down: a held
        /// finger keeps its row lit for as long as it is held.
        ///
        /// **A row that never lit has nothing to put out.** That covers the swipe case: the
        /// finger went sideways and the press was cancelled before the mark was drawn, so
        /// this only cancels the timer that was going to draw it.
        private func unlight() {
            lighting?.cancel()
            lighting = nil
            guard lit else { return }

            release?.cancel()
            release = Task { @MainActor in
                try? await Task.sleep(for: RowPress.hold)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: RowPress.fade)) { lit = false }
            }
        }
    }

    /// What the row actually draws. The press reaches here when the list lets it
    /// through, which is on a hold. On a tap this only draws what the action lit.
    private struct Mark: ButtonStyle {
        let lit: Bool
        let down: () -> Void
        let up: () -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(RPMInk.white(0x24 / 255).opacity(lit ? 1 : 0))
                .contentShape(Rectangle())
                // A scroll begun on a row never gets here: a drag cancels the press
                // before it is recognised.
                .onChange(of: configuration.isPressed) { _, pressed in
                    pressed ? down() : up()
                }
        }
    }
}
