import SwiftUI
import RPMAudio
import RPMKit
import RPMLibrary
import RPMArt
import RPMDesign
import RPMSession
import RPMSharedUI

/// What a record page shows: a record, or a list.
enum RecordOf {
    case album(CloudAlbum)
    case list(PlaylistSet)
    /// The account's favourite songs, as the phone lists them: every marked song, by record.
    case favourites([CloudTrack])
}

/// The record page, and the list page, which is the same page (the desktop's Record and
/// RecordList): the sleeve with the record half out of it and turning, the names, the keys and
/// what the encyclopedias say on the left; the tracks on the right. The room behind is lit from
/// the sleeve.
///
/// Select on a track plays from it; press and hold opens its menu. The heart marks the record on
/// the account's own collection.
struct RecordPage: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let of: RecordOf
    let page: Page

    /// The record slides out of the sleeve as the page opens.
    @State private var out = false
    /// Whether the stars card is up (Rate album in the page's menu).
    @State private var rating = false
    @FocusState private var playFocused: Bool
    @Environment(\.displayScale) private var scale

    private var tracks: [CloudTrack] {
        // The order being worked on while a row is moved; the list's own otherwise.
        if let working { return working }
        switch of {
        case .album(let album): return album.tracks
        case .list(let set): return set.tracks
        case .favourites(let tracks): return tracks
        }
    }

    /// The list's order while a row is being moved, with the row where the keys have carried it.
    @State private var working: [CloudTrack]?
    /// The row being moved: where it started and where it is now.
    @State private var moving: (from: Int, at: Int)?
    @FocusState private var focusedRow: Int?

    /// The list, where it may be rearranged: the account's own, made by somebody, and with every
    /// song in it here (the whole order goes up on a write, and one holding songs this device
    /// cannot see would lose them), as the phone allows it.
    private var reorderable: PlaylistSet? {
        guard case .list(let set) = of, set.isWritable, set.missing == 0 else { return nil }
        return set
    }

    private func rowMove(at: Int) -> RowMove? {
        guard let set = reorderable else { return nil }
        return RowMove(
            isMoving: moving?.at == at,
            begin: {
                working = set.tracks
                moving = (at, at)
                focusedRow = at
            },
            step: { by in
                guard var order = working, let now = moving, order.indices.contains(now.at + by) else { return }
                order.swapAt(now.at, now.at + by)
                working = order
                moving = (now.from, now.at + by)
                focusedRow = now.at + by
            },
            place: {
                guard let now = moving else { return }
                moving = nil
                guard now.from != now.at else { working = nil; return }
                Task {
                    // One write, for where it started and where it ended. The working order stays
                    // on the screen until the list comes back in it.
                    if let trouble = await model.session.reorderPlaylist(set, from: now.from, to: now.at) {
                        model.flash(trouble)
                    }
                    working = nil
                }
            })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 90) {
            left
                .frame(width: 620)
            tracksColumn
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Size.side + 20)
        // Below the sidebar's pill, which stands over the top left of every page, and inside the
        // foot's margin: the column under the sleeve is fitted into what is left.
        .padding(.top, Size.belowPill)
        .padding(.bottom, Size.top)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42).delay(0.1)) { out = true }
        }
        // The list read again under a move (changed elsewhere): the move ends where it is, as the
        // queue drawer's does, so a write never moves a row within an order nobody is looking at.
        .onChange(of: reorderable?.tracks.map(\.rpmId)) { _, _ in
            guard moving != nil else { return }
            moving = nil
            working = nil
        }
        // Back puts a row being moved back where it started; otherwise it leaves the page.
        .onExitCommand(perform: moving == nil ? nil : {
            let row = moving?.from
            moving = nil
            working = nil
            focusedRow = row
        })
        .defaultFocus($playFocused, true)
        .sheet(isPresented: $rating) {
            if case .album(let album) = of, let account = model.session.who?.userId {
                StarsCard(stars: model.ratings.stars(of: album, account: account)) { picked in
                    model.ratings.rate(album, stars: picked, account: account)
                }
            }
        }
    }

    /// The stars given this record on this TV under the signed-in account; nil off a record.
    private var givenStars: Int? {
        guard case .album(let album) = of, let account = model.session.who?.userId else { return nil }
        return model.ratings.stars(of: album, account: account)
    }

    // ── the left column ──

    private var left: some View {
        VStack(spacing: 18) {
            ZStack {
                RecordDisc(diameter: 400 * 0.96, halo: .cast, spinning: model.player.isPlaying && isPlayingHere,
                           hue: hue, label: label?.image)
                    .offset(x: out ? 400 * 0.312 : 0)
                // No shadow of its own, as on the desktop: the record casts one, the sleeve none.
                sleeve
            }
            .frame(width: 400, height: 400)
            .offset(x: -60)

            Text(title)
                .font(.tv(44, .bold))
                .foregroundStyle(Ink.words)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let line {
                if case .album(let album) = of {
                    // The artist's page, as the phone's record page offers it.
                    Button {
                        screens.open(.artist(album.artist))
                    } label: {
                        Text(line)
                            .font(.tv(Size.row))
                            .foregroundStyle(Color.white.opacity(0xD9 / 255))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(line)
                        .font(.tv(Size.row))
                        .foregroundStyle(Color.white.opacity(0xD9 / 255))
                        .lineLimit(1)
                }
            }
            // The count, and on a record the file's format after it in italics (read off the first
            // track that has one, as the phone's record page), on one line so the article keeps
            // its room.
            let count = Text(countLine).foregroundStyle(Color.white.opacity(0xB0 / 255))
            let format = Text(formatLine.isEmpty ? "" : "   " + formatLine)
                .italic()
                .foregroundStyle(Color.white.opacity(0x8A / 255))
            Text("\(count)\(format)")
                .font(.tv(Size.rowLine))
                .lineLimit(1)
            // The stars given the record on this TV, where it has some (the Android TV's line).
            if let stars = givenStars, stars > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<AlbumRatings.most, id: \.self) { i in
                        Image(systemName: i < stars ? "star.fill" : "star")
                            .font(.system(size: 22))
                            .foregroundStyle(i < stars ? Ink.words : Color.white.opacity(0.4))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Loc.get("Review_Stars", String(stars)))
            }

            HStack(spacing: 20) {
                Button {
                    model.play(tracks, from: 0)
                    screens.playerShown = true
                } label: {
                    Label(isAlbum ? Loc.get("AlbumGrid_PlayAll") : Loc.get("Playlists_Play"), systemImage: "play.fill")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.glassProminent)
                .focused($playFocused)

                // The page's menu, as the Android TV's key beside Play: Shuffle,
                // Add to queue and Play next, and on a record of the account's own collection Favourite
                // album and Rate album.
                Menu {
                    Button(isAlbum ? Loc.get("AlbumGrid_Shuffle") : Loc.get("AlbumMenu_Shuffle"), systemImage: "shuffle") {
                        model.shuffle(tracks)
                        screens.playerShown = true
                    }
                    Button(Loc.get("Tv_Album_AddToQueue"), systemImage: "text.append") {
                        model.addToQueue(tracks, named: title)
                    }
                    Button(Loc.get("AlbumMenu_PlayNext"), systemImage: "text.line.first.and.arrowtriangle.forward") {
                        model.playNext(tracks, named: title)
                    }
                    if case .album(let album) = of, model.session.viewing.isOwn {
                        let marked = model.session.isMarked(album)
                        Divider()
                        Button(marked ? Loc.get("Album_UnsetFavorite") : Loc.get("AlbumMenu_Favorite"),
                               systemImage: marked ? "heart.slash" : "heart") {
                            Task { await model.session.mark(album, !marked) }
                        }
                        Button(Loc.get("Tv_Album_Rate"), systemImage: "star") { rating = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.glass)

                // Another selection of a generated list, where the computer sent enough of it.
                if case .list(let set) = of, model.session.hasAnotherList(set) {
                    Button {
                        model.session.newGeneratedList(set)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(Loc.get("Playlists_GenerateNew"))
                }

                if case .album(let album) = of, model.session.viewing.isOwn {
                    let marked = model.session.isMarked(album)
                    Button {
                        Task { await model.session.mark(album, !marked) }
                    } label: {
                        Image(systemName: marked ? "heart.fill" : "heart")
                            .keyTint(marked ? Ink.loved : nil)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.top, 8)
            .focusSection()

            if case .album(let album) = of {
                // The first to give way: the article loses lines before anything above it moves.
                AboutRecord(album: album)
                    .layoutPriority(-1)
            }
            // What a list is and who is on it, as the phone's list page says it: a mood's
            // sentence, then "Featuring" and the artists.
            if case .list(let set) = of, let about = PlaylistFeatures.line(blurb: blurb(set), credits: tracks.map(\.artist)) {
                Text(about)
                    .font(.tv(24))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.top, 10)
                    .layoutPriority(-1)
            }
        }
        // Top-aligned in the room the page gives it, rather than a spacer at the foot: a spacer
        // is offered the room before the article, which gives way first, and would take all of it.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var sleeve: some View {
        switch of {
        case .album(let album):
            Sleeve(album: album, edge: 400, corner: 8, onColours: { screens.paint(page, $0) })
        case .list(let set):
            ListPicture(set: set, edge: 400, corner: 8, drifts: true, onColours: { screens.paint(page, $0) })
        case .favourites:
            FavouritesPicture(edge: 400, corner: 8)
        }
    }

    /// The record's own sleeve, for its label, read from the store the sleeve was drawn from.
    @State private var art: CoverArt?

    /// The label's picture: as read, else as the store last handed it out, so the record comes out
    /// of the sleeve already wearing it.
    private var label: CoverArt? {
        guard case .album(let album) = of else { return nil }
        return art ?? model.artwork.coverInMemory(for: album, on: model.session.shelves.shelf(ofAlbum: album),
                                                  edge: Self.labelEdge)
    }

    private static let labelEdge = 256

    private var hue: RGB? { label?.accent?.base ?? VinylPressing.houseHue }

    private var isAlbum: Bool { if case .album = of { true } else { false } }

    /// A record's year where its tracks give one, as the Android TV's record page leads with it; how
    /// many songs and how long; and on a list how many are not in the cloud yet (a computer can send a
    /// list's order before its audio is up), as the phone says it.
    private var countLine: String {
        var said = (tracks.count == 1 ? Loc.get("Rpm_Album_TracksOne") : Loc.get("Rpm_Album_Tracks", String(tracks.count)))
            + "  ·  " + clock(tracks.reduce(0) { $0 + $1.duration.seconds })
        if isAlbum, case let year = AlbumSort.yearOf(tracks), year > 0 {
            said = String(year) + "  ·  " + said
        }
        if case .list(let set) = of, set.missing > 0 {
            said += "  ·  " + (set.missing == 1 ? Loc.get("Rpm_Playlist_MissingOne")
                                                : Loc.get("Rpm_Playlist_Missing", String(set.missing)))
        }
        return said
    }

    private var formatLine: String {
        guard isAlbum, let format = tracks.compactMap(\.tags).first(where: \.hasFormat)?.format else { return "" }
        return format.joined(separator: " · ")
    }

    /// A generated mood list's sentence, or nil.
    private func blurb(_ set: PlaylistSet) -> String? {
        guard set.origin == .generated, let cut = set.cut else { return nil }
        return MoodBlurb.sentence(kind: cut.kind, genres: tracks.map { $0.tags?.genre })
    }

    private var isPlayingHere: Bool {
        guard let current = model.player.current else { return false }
        return tracks.contains { $0.rpmId == current.rpmId }
    }

    private var title: String {
        switch of {
        case .album(let album): AlbumNames.title(album)
        case .list(let set): set.name
        case .favourites: Loc.get("Playlists_FavoriteTracks")
        }
    }

    private var line: String? {
        switch of {
        case .album(let album): album.artist.isEmpty ? nil : album.artist
        case .list(let set): set.folder.isEmpty ? nil : set.folder.joined(separator: " / ")
        case .favourites: nil
        }
    }

    // ── the tracks ──

    private var tracksColumn: some View {
        let albums = Dictionary(model.session.albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let discs = Set(tracks.map { max(1, $0.tags?.discNumber ?? 1) }).count
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { at, track in
                    let disc = max(1, track.tags?.discNumber ?? 1)
                    if isAlbum, discs > 1, at == 0 || max(1, tracks[at - 1].tags?.discNumber ?? 1) != disc {
                        DiscHeading(disc: disc)
                    }
                    TrackRow(track: track,
                             number: isAlbum ? ((track.tags?.trackNumber ?? 0) > 0 ? track.tags!.trackNumber : at + 1) : at + 1,
                             album: albums[AlbumGrouping.key(for: track)],
                             line: rowLine, queue: tracks, at: at, move: rowMove(at: at))
                        .focused($focusedRow, equals: at)
                }
            }
            // The first row level with the top of the sleeve.
            .padding(.bottom, 20)

            // Other records on this collection to play after this one, as the phone's record page
            // has them under its songs.
            if !similar.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Loc.get("Album_SimilarAlbums"))
                        .font(.tv(Size.heading, .semibold))
                        .foregroundStyle(Ink.card)
                        .padding(.leading, RowStyle.inset)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 32) {
                            ForEach(similar) { AlbumCard(album: $0, edge: 200) }
                        }
                        .padding(.horizontal, RowStyle.inset)
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                }
                .padding(.top, 30)
                .padding(.bottom, 60)
                .transition(.opacity)
            }

            // What everybody else made of it, as the phone's record page ends: read, not written.
            if case .album(let album) = of {
                ReviewsBlock(album: album)
                    .padding(.bottom, 60)
            }
        }
        .scrollClipDisabled()
        .focusSection()
        .task(id: albumKey) {
            guard case .album(let album) = of else { return }
            art = await model.artwork.cover(for: album, on: model.session.shelves.shelf(ofAlbum: album), edge: Self.labelEdge)
            // The artist line opens their page: its photograph and text, ready before it is asked.
            await model.warmArtist(album.artist, scale: scale)
        }
        .task(id: albumKey) {
            similar = []
            guard case .album(let album) = of else { return }
            // Ranked off the main actor: it walks every track on the collection.
            let shelf = model.session.albums
            let row = await Task.detached(priority: .utility) { SimilarAlbums.row(for: album, on: shelf) }.value
            guard !Task.isCancelled else { return }
            // Under the songs, so it moves nothing; faded in rather than put up at once.
            withAnimation(.easeOut(duration: 0.35)) { similar = row }
        }
    }

    /// Other records like this one, worked out when the page opens.
    @State private var similar: [CloudAlbum] = []

    /// A record whose tracks are not all by its artist (a compilation) shows each track's artist;
    /// any other record none; a list, its artists and records.
    private var rowLine: TrackRow.Line {
        guard case .album(let album) = of else { return .artistAndAlbum }
        let own = album.artist
        return album.tracks.contains { ($0.artist ?? own).caseInsensitiveCompare(own) != .orderedSame } ? .artist : .none
    }

    private var albumKey: String? { if case .album(let album) = of { album.key } else { nil } }
}

/// "CD n" over a disc's first track, with a hairline under it.
private struct DiscHeading: View {
    let disc: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.get("Album_DiscHeader", String(disc)))
                .font(.tv(24, .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
    }
}

/// One track: its number (or, with none, its record's sleeve), its title with the E, on a list its
/// artist and record under it, and its length. Select plays the queue from it; press and hold opens its menu.
struct TrackRow: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let track: CloudTrack
    let number: Int?
    let album: CloudAlbum?
    let line: Line

    /// The line under a track's title.
    enum Line {
        /// None: a record's own tracks, all by its artist.
        case none
        /// The track's artist: a compilation's tracks, each by its own.
        case artist
        /// The artist and the record: a list, search results, popular tracks.
        case artistAndAlbum
    }
    let queue: [CloudTrack]
    let at: Int
    /// How this row moves in its list, on a list that may be rearranged; nil everywhere else.
    var move: RowMove? = nil

    var body: some View {
        let playing = model.player.current?.rpmId == track.rpmId
        let moving = move?.isMoving == true
        Button {
            // Select places a row being moved; otherwise it plays the list from here.
            if moving { move?.place(); return }
            model.play(queue, from: at)
            screens.playerShown = true
        } label: {
            HStack(spacing: 22) {
                if move != nil {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.white.opacity(moving ? 1 : 0.3))
                }
                ZStack {
                    if playing {
                        Image(systemName: model.player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Ink.words)
                    } else if let number {
                        Text(String(number))
                            .font(.tv(Size.row).monospacedDigit())
                            .foregroundStyle(Color.white.opacity(0.45))
                    } else {
                        // A song found by search has no place in a list: its record's sleeve stands
                        // where the number would.
                        Sleeve(album: album, edge: 56, corner: 6)
                    }
                }
                .frame(width: 56, height: 56, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(track.title ?? "")
                            .font(.tv(Size.row))
                            .foregroundStyle(Ink.words)
                            .lineLimit(1)
                        if track.isExplicit { ExplicitMark(side: 26) }
                    }
                    if line != .none {
                        Text((line == .artist ? [track.artist] : [track.artist, album?.album ?? track.album])
                            .compactMap { $0 }.filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.tv(Size.rowLine))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 20)
                if track.duration > .zero {
                    Text(clock(track.duration.seconds))
                        .font(.tv(Size.rowLine).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
        .buttonStyle(RowStyle())
        .opacity(moving ? 0.86 : 1)
        .onMoveCommand { direction in
            guard moving else { return }
            switch direction {
            case .up: move?.step(-1)
            case .down: move?.step(1)
            default: break
            }
        }
        .contextMenu {
            if !moving {
                TrackMenu(track: track, queue: queue, at: at)
                if let move {
                    Button(Loc.get("Viz_QueueMove"), systemImage: "arrow.up.arrow.down") { move.begin() }
                }
            }
        }
    }
}

/// How one row of a list that may be rearranged moves: begun from its menu, carried a place at a
/// time with Up and Down, placed with Select, put back with Back.
struct RowMove {
    let isMoving: Bool
    let begin: () -> Void
    let step: (Int) -> Void
    let place: () -> Void
}

/// A track's menu: Play, Play next and Add to Now playing, then, on the account's own collection,
/// the favourite mark and Add to playlist, which offers a new playlist and lists the account's own,
/// ticked where the track is already in one. A borrowed collection is not written to from here.
struct TrackMenu: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let track: CloudTrack
    let queue: [CloudTrack]
    let at: Int

    var body: some View {
        Button(Loc.get("AlbumMenu_Play"), systemImage: "play.fill") {
            model.play(queue, from: at)
            screens.playerShown = true
        }
        Button(Loc.get("AlbumMenu_PlayNext"), systemImage: "text.line.first.and.arrowtriangle.forward") {
            model.playNext(track)
        }
        Button(Loc.get("Playlists_AddToNowPlaying"), systemImage: "text.line.last.and.arrowtriangle.forward") {
            model.addToQueue(track)
        }
        // On a borrowed collection too: a radio only plays, it writes nothing.
        Button(Loc.get("Track_StartMixtape"), systemImage: "recordingtape") {
            model.startRadio(track)
            screens.playerShown = true
        }
        if model.session.isTrackMine(track) {
            if model.session.isTrackMarked(track) {
                Button(Loc.get("Track_UnsetFavorite"), systemImage: "heart.slash") { model.mark(track, false) }
            } else {
                Button(Loc.get("Track_SetFavorite"), systemImage: "heart") { model.mark(track, true) }
            }
            AddToPlaylistMenu(track: track)
        }
    }
}

/// Add to playlist: a new list from the song, then the account's own lists, ticked where the song
/// already is. In the song menu and the player's More menu.
struct AddToPlaylistMenu: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let track: CloudTrack

    var body: some View {
        let own = model.session.playlists.filter(\.isWritable)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        Menu {
            Button(Loc.get("Playlists_NewPlaylistFrom"), systemImage: "plus") { screens.naming = track }
            Divider()
            // The lists in no folder, then a submenu for each folder, as the phone browses them.
            ForEach(own.filter { $0.folder.isEmpty }) { set in entry(set) }
            ForEach(PlaylistsView.folders(own), id: \.self) { folder in
                Menu {
                    ForEach(own.filter { $0.folder == folder }) { set in entry(set) }
                } label: {
                    Label(folder.joined(separator: " / "), systemImage: "folder")
                }
            }
        } label: {
            Label(Loc.get("Playlists_AddToPlaylist"), systemImage: "text.badge.plus")
        }
    }
}

extension AddToPlaylistMenu {
    /// One list: ticked where the song already is. A list may hold a song twice, and nobody means
    /// it by accident: asked first, as on the phone.
    @ViewBuilder
    func entry(_ set: PlaylistSet) -> some View {
        let holds = set.tracks.contains { $0.rpmId == track.rpmId }
        Button(set.name, systemImage: holds ? "checkmark" : "music.note.list") {
            if holds {
                screens.fileAgain = FileAgain(track: track, list: set)
            } else {
                model.file(track, in: set, whenAlreadyThere: .leaveIt)
            }
        }
    }
}

/// The sleep timer (the phone's): while off, the waits and End of song; while on, when it stops,
/// time to add, and Turn off.
struct SleepTimerMenu: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        let player = model.player
        Menu {
            if player.sleepTimer.isOn {
                Section(stopsLine) {
                    ForEach(SleepTimer.durations, id: \.self) { wait in
                        Button(SleepWords.adding(wait)) { player.addSleepTime(wait) }
                    }
                    Button(Loc.get("Rpm_Sleep_TurnOff"), role: .destructive) { player.turnOffSleepTimer() }
                }
            } else {
                ForEach(SleepTimer.durations, id: \.self) { wait in
                    Button(SleepWords.after(wait)) { player.setSleepTimer(.after(wait)) }
                }
                // A station has no end to wait for.
                if player.station == nil {
                    Button(Loc.get("Rpm_Sleep_EndOfSong")) { player.setSleepTimer(.endOfTrack) }
                }
            }
        } label: {
            Label(Loc.get("Rpm_Sleep_Title"), systemImage: player.sleepTimer.isOn ? "moon.zzz.fill" : "moon.zzz")
        }
    }

    /// When playback stops, as a clock time, or the end of the song. Read when the menu opens.
    private var stopsLine: String {
        let player = model.player
        if player.sleepTimer.endsWithTheTrack { return Loc.get("Rpm_Sleep_StopsAtEndOfSong") }
        guard let left = player.sleepTimeLeft(at: .now) else { return "" }
        let at = Date.now.addingTimeInterval(left.seconds)
        return Loc.get("Rpm_Sleep_StopsAt", at.formatted(date: .omitted, time: .shortened))
    }
}

/// A block of text that opens more of itself: lit under the focus by a ground drawn round it, which
/// takes no room from the text, unlike a row's padding.
struct ProseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProseBody(configuration: configuration)
    }

    private struct ProseBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(focused ? 0.16 : 0))
                        .padding(-12)
                }
                .scaleEffect(configuration.isPressed ? 0.99 : (focused ? 1.02 : 1))
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// A row of a list: lit under the focus as a search result is, and grown a little.
struct RowStyle: ButtonStyle {
    /// How far a row's content stands in from the row's edges, so a heading over rows can line up.
    static let inset: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .padding(.horizontal, RowStyle.inset)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(focused ? 0.2 : 0))
                }
                .scaleEffect(configuration.isPressed ? 0.98 : (focused ? 1.02 : 1))
                .shadow(color: .black.opacity(focused ? 0.3 : 0), radius: 14, y: 6)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// What the encyclopedias say about a record, under its keys: the genres it is filed under, as
/// chips, and the opening paragraph of its Wikipedia article, cut at the last sentence that fits.
/// The turning record stands where the words will be while the article is asked for; nothing is
/// shown if it fails or finds nothing.
private struct AboutRecord: View {
    @Environment(TVModel.self) private var model
    let album: CloudAlbum

    @State private var article: EncyclopediaArticle?
    @State private var articleOf: String?
    @State private var waiting = false
    @State private var reading = false

    var body: some View {
        var readings: [String: String?] = [:]
        let genres = Array(Genres.of(album.tracks, readings: &readings).prefix(6))
        // From memory on the first frame where it was read before, so a page opened again does not
        // fill in under the eyes.
        let subject = ArticleStore.Subject.album(artist: album.artist, title: album.album, tracks: album.tracks.count)
        let article = articleOf == album.key ? self.article : model.articles.cached(subject)

        return VStack(spacing: 16) {
            if !genres.isEmpty {
                FlowChips(items: genres)
            }
            if waiting, article == nil {
                RecordSpinner(diameter: 40)
                    .transition(.opacity)
            } else if let article, let lead = article.paragraphs.first, !lead.isEmpty {
                // Select opens the whole article, as the phone's page does.
                Button { reading = true } label: {
                    Text(Prose.lead(lead, lines: 10, perLine: 46))
                        .font(.tv(24))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(10)
                }
                .buttonStyle(ProseStyle())
                .transition(.opacity)
                .sheet(isPresented: $reading) {
                    ArticleSheet(heading: Loc.get("TrackInfo_AboutAlbum"), name: AlbumNames.title(album), article: article)
                }
            }
        }
        .padding(.top, 10)
        .task(id: album.key) {
            if model.articles.cached(subject) != nil { return }
            withAnimation(.easeOut(duration: 0.3)) { waiting = true }
            let found = await model.articles.article(subject)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.9)) {
                self.article = found
                articleOf = album.key
                waiting = false
            }
        }
    }
}

/// A whole article, under what it is about: every paragraph, scrolled by the remote. Back closes it.
struct ArticleSheet: View {
    let heading: String
    let name: String
    let article: EncyclopediaArticle

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                Text(heading.uppercased())
                    .font(.tv(Size.small, .semibold))
                    .tracking(2)
                    .foregroundStyle(Ink.dim)
                Text(name)
                    .font(.tv(48, .bold))
                    .foregroundStyle(Ink.words)
                ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    // Focusable, so the remote can scroll the article a paragraph at a time.
                    Text(paragraph)
                        .font(.tv(28))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusable()
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(60)
        }
    }
}

/// An article's opening paragraph, cut at the last sentence that ends within the room, so the
/// reader is not handed an ellipsis in the middle of a name (the desktop's Shorten, as the Android
/// TV cuts it). The room is counted in characters, which is an estimate: the line limit on the text
/// is what holds it, and a cut that came out long ends in an ellipsis there.
enum Prose {
    static func lead(_ paragraph: String, lines: Int, perLine: Int) -> String {
        let room = lines * perLine
        guard paragraph.count > room else { return paragraph }
        let head = paragraph.prefix(room)
        let ends = head.indices.filter { at in
            ".!?".contains(head[at]) && (head.index(after: at) == head.endIndex || head[head.index(after: at)].isWhitespace)
        }
        // A first sentence longer than the room is left whole for the line limit to end.
        guard let last = ends.last else { return paragraph }
        return String(head[...last])
    }
}

/// Chips that wrap onto the next line.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.tv(23))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0x1F / 255), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

/// Lays its children in rows, centred, wrapping where the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// A record's reviews from the community, read only (the phone's ReviewsWall): the average of
/// everybody's stars and how many, then the reviews with the most votes, each opening whole on
/// Select. Nothing at all where the community cannot be reached.
private struct ReviewsBlock: View {
    @Environment(TVModel.self) private var model
    let album: CloudAlbum

    @State private var entry: RPMAlbum?
    @State private var reviews: [RPMReview] = []
    @State private var failed = false
    @State private var open: RPMReview?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if entry != nil || failed {
                Text(heading)
                    .font(.tv(Size.heading, .semibold))
                    .foregroundStyle(Ink.card)
                    .padding(.leading, RowStyle.inset)
            }
            if failed {
                Text(Loc.get("Album_CommunityOffline"))
                    .font(.tv(Size.small)).foregroundStyle(Ink.dim)
                    .padding(.leading, RowStyle.inset)
            } else if entry != nil, reviews.isEmpty {
                Text(Loc.get("Album_NoReviews"))
                    .font(.tv(Size.small)).foregroundStyle(Ink.dim)
                    .padding(.leading, RowStyle.inset)
            }
            ForEach(reviews.filter { !$0.authorDeleted }, id: \.self.reviewKey) { review in
                Button { open = review } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Text(review.authorName)
                                .font(.tv(Size.rowLine, .semibold))
                                .foregroundStyle(Ink.words)
                            Stars(rating: review.rating)
                        }
                        Text(review.body)
                            .font(.tv(Size.small))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(RowStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $open) { review in
            ReviewSheet(review: review, record: AlbumNames.title(album))
        }
        .task(id: album.key) {
            entry = nil; reviews = []; failed = false
            do {
                // The community's page for this pressing, asked by the tags this app holds, as the
                // phone asks it; then its reviews with the most votes.
                let found = try await model.community.resolveAlbum(
                    artist: album.artist, title: album.album,
                    year: AlbumSort.yearOf(album.tracks), trackCount: album.tracks.count)
                let page = try await model.community.reviews(albumId: found.albumId, sort: .votes,
                                                             page: 1, pageSize: 6)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    entry = found
                    reviews = page.items
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.35)) { failed = true }
            }
        }
    }

    /// "Reviews · 4.5 of 5 (12)", or "Reviews" with none rated.
    private var heading: String {
        guard let entry, entry.ratingCount > 0 else { return Loc.get("Album_ReviewsHeading") }
        return Loc.get("Rpm_Album_ReviewsRated",
                       entry.averageRating.formatted(.number.precision(.fractionLength(0...1))),
                       String(entry.ratingCount))
    }
}

extension RPMReview: @retroactive Identifiable {
    public var id: String { reviewKey }
}

extension RPMReview {
    /// One review: its album and its author.
    var reviewKey: String { albumId + "/" + userId }
}

/// A review's stars: its rating is halves of a star, 1 to 10.
private struct Stars: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { star in
                let left = rating - star * 2
                Image(systemName: left >= 2 ? "star.fill" : left == 1 ? "star.leadinghalf.filled" : "star")
            }
        }
        .font(.system(size: 18))
        .foregroundStyle(Ink.gold)
        .accessibilityLabel(Loc.get("Rpm_Album_ReviewsRated", String(Double(rating) / 2), "1"))
    }
}

/// One review whole: who wrote it, their stars, and all of what they wrote. Back closes it.
private struct ReviewSheet: View {
    let review: RPMReview
    let record: String

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                Text(record.uppercased())
                    .font(.tv(Size.small, .semibold)).tracking(2).foregroundStyle(Ink.dim)
                HStack(spacing: 16) {
                    Text(review.authorName).font(.tv(40, .bold)).foregroundStyle(Ink.words)
                    Stars(rating: review.rating)
                }
                Text(review.body)
                    .font(.tv(28))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(6)
                    .focusable()
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(60)
        }
    }
}

/// Stars asked for over the record page (Rate album in its menu), as the Android TV's stars card: the
/// entry's words as a heading, five stars, and Cancel and Rate under them. Select on a star gives that
/// many; on the highest one lit, one fewer, so the first star pressed again leaves none. Rate hands the
/// stars to `onRate` and closes the card; Cancel and Back close it.
struct StarsCard: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stars: Int
    let onRate: (Int) -> Void

    init(stars: Int, onRate: @escaping (Int) -> Void) {
        _stars = State(initialValue: min(max(stars, 0), AlbumRatings.most))
        self.onRate = onRate
    }

    var body: some View {
        VStack(spacing: 40) {
            Text(Loc.get("Tv_Album_Rate"))
                .font(.tv(Size.heading, .semibold))
                .foregroundStyle(Ink.words)

            HStack(spacing: 24) {
                ForEach(0..<AlbumRatings.most, id: \.self) { i in
                    Button {
                        stars = stars == i + 1 ? i : i + 1
                    } label: {
                        Image(systemName: i < stars ? "star.fill" : "star")
                            .font(.system(size: 44))
                            .foregroundStyle(i < stars ? Ink.words : Color.white.opacity(0.45))
                            .frame(width: 80, height: 80)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Loc.get("Review_Stars", String(i + 1)))
                }
            }
            .focusSection()

            HStack(spacing: 30) {
                Button(Loc.get("Common_Cancel")) { dismiss() }
                    .buttonStyle(.glass)
                Button(Loc.get("Tv_Album_RateConfirm")) {
                    onRate(stars)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
            .focusSection()
        }
        .padding(60)
    }
}

