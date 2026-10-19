import SwiftUI
import RPMKit
import RPMLibrary
import RPMArt
import RPMDesign
import RPMSession
import RPMSharedUI

// MARK: Playlists

/// The playlists screen: first the lists that the computer made, then the account's own lists.
/// Each list opens its list page.
struct PlaylistsView: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        let session = model.session
        let generated = session.playlists.filter { $0.origin == .generated }
        // The account's own lists, without the empty ones, as in the Android TV app.
        let stored = session.playlists.filter { $0.origin != .generated && !$0.tracks.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // The favourite songs as a list, as on the phone. Only for the account's own collection.
        let favourites = session.viewing.isOwn ? session.favoriteTracks : []

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                PageBar(Counts.playlists(generated.count + stored.count))

                switch session.playlistStanding {
                case .reading:
                    Waiting(Loc.get("Rpm_Playlists_Loading")).frame(height: 500)
                case .trouble(let said):
                    Trouble(said) { Task { await session.loadPlaylists() } }.frame(height: 500)
                case .showing:
                    if generated.isEmpty, stored.isEmpty, favourites.isEmpty {
                        Message(Loc.get("Viz_BrowseNoPlaylists")).frame(height: 500)
                    }
                    if !generated.isEmpty {
                        Heading(Loc.get("Home_MadeForYou"))
                        ListGrid(sets: generated, favourites: [])
                    }
                    // The account's own lists, with a section for each folder. The phone opens a
                    // folder as a separate step, and the TV shows the folders one under another.
                    // Lists that are in no folder, and the favourite songs, come first under
                    // "Playlists".
                    let loose = stored.filter { $0.folder.isEmpty }
                    if !loose.isEmpty || !favourites.isEmpty {
                        Heading(Loc.get("Playlists_Title"))
                        ListGrid(sets: loose, favourites: favourites)
                    }
                    ForEach(Self.folders(stored), id: \.self) { folder in
                        Heading(folder.joined(separator: " / "))
                        ListGrid(sets: stored.filter { $0.folder == folder }, favourites: [], underFolder: true)
                    }
                }
            }
            .padding(.top, Size.top)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .task { await session.showPlaylists() }
    }

    /// Every folder that contains a list, in name order.
    static func folders(_ sets: [PlaylistSet]) -> [[String]] {
        Array(Set(sets.map(\.folder).filter { !$0.isEmpty }))
            .sorted { $0.joined(separator: "/").localizedStandardCompare($1.joined(separator: "/")) == .orderedAscending }
    }
}

private struct ListGrid: View {
    let sets: [PlaylistSet]
    /// The favourite songs, drawn as the first card. No card is drawn when the array is empty.
    let favourites: [CloudTrack]
    /// Whether the grid is under its folder's heading, so the folder name is not repeated on each
    /// list.
    var underFolder = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Card.edge), spacing: Card.gap), count: AlbumGrid.columns),
                  alignment: .leading, spacing: 56) {
            if !favourites.isEmpty { FavouritesCard(tracks: favourites) }
            ForEach(sets) { ListCard(set: $0, edge: Card.edge, onShelf: !underFolder) }
        }
        .padding(.horizontal, Size.side)
        .focusSection()
    }
}

// MARK: Artists

/// The artists list: a round photograph for each artist, with the artist's initial shown while
/// the photograph loads. The list has four sort orders. A new order scrolls back to the top.
struct ArtistsView: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    @AppStorage("tv.artists.order") private var orderName = ArtistOrdering.name.rawValue
    @State private var read = ReadArtists()

    private var order: ArtistOrdering { ArtistOrdering(rawValue: orderName) ?? .name }

    var body: some View {
        let artists = read.artists(model.session.albums, in: order)

        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 30) {
                    PageBar(artists.count == 1 ? Loc.get("Artists_CountOne") : Loc.get("Artists_Count", String(artists.count))) {
                        Menu {
                            Picker(Loc.get("Viz_ArtistsSort"), selection: $orderName) {
                                ForEach(ArtistOrdering.allCases, id: \.self) { ordering in
                                    Text(Self.label(ordering)).tag(ordering.rawValue)
                                }
                            }
                        } label: {
                            Label(Self.label(order), systemImage: "arrow.up.arrow.down")
                        }
                        .buttonStyle(.glass)
                        .remembered("order")
                    }
                    // The position that the list scrolls to when the order changes.
                    .id("top")

                    if artists.isEmpty {
                        Message(Loc.get("Artists_Empty")).frame(height: 400)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(ArtistCard.edge), spacing: Card.gap),
                                                 count: ArtistCard.columns),
                                  alignment: .leading, spacing: 56) {
                            ForEach(artists) { artist in
                                ArtistCard(artist: artist) { screens.open(.artist(artist.name)) }
                            }
                        }
                        .padding(.horizontal, Size.side)
                    }
                }
                .padding(.top, Size.top)
                .padding(.bottom, 80)
            }
            .scrollClipDisabled()
            .onChange(of: orderName) { _, _ in
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    static func label(_ order: ArtistOrdering) -> String {
        switch order {
        case .name: Loc.get("ArtistSort_Name")
        case .albums: Loc.get("ArtistSort_Albums")
        case .tracks: Loc.get("ArtistSort_Tracks")
        case .added: Loc.get("ArtistSort_Added")
        }
    }
}

/// An artist on the list or on a genre's page: the round photograph and the name.
struct ArtistCard: View {
    /// Seven round photographs fit between the margins, with six gaps between them.
    static let columns = 7
    static let edge: CGFloat = (1920 - 2 * Size.side - CGFloat(columns - 1) * Card.gap) / CGFloat(columns)

    let artist: ArtistWallItem
    var edge: CGFloat = ArtistCard.edge
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Portrait(artist: artist.name, edge: edge)
                .hoverEffect(.highlight)
            // The name only, as in the Android TV app. There is no count of records under it.
            Text(artist.name)
                .font(.tv(Size.cardTitle, .semibold))
                .foregroundStyle(Ink.card)
                .lineLimit(1)
                .frame(width: edge + 20)
        }
        .buttonStyle(.borderless)
        // The focus effect is a circle, to match the round photograph.
        .buttonBorderShape(.circle)
        .remembered("artist:" + artist.name)
    }
}

/// An artist's page: the photograph, the number of records and songs, and the Play all and Shuffle
/// buttons. Below these are the artist's popular songs, then rows of the artist's records by kind,
/// the playlists and mood playlists that contain the artist's songs, and the related artists in
/// the collection. The room takes its colour from the photograph.
struct ArtistPage: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let name: String
    let page: Page
    @State private var read = ReadArtists()
    @State private var readGenres = ReadGenres()
    /// The related artists (``RelatedArtists``), and the `RelatedAsk` that they were read for.
    @State private var related: (ask: RelatedAsk, acts: [ArtistWallItem])?
    /// The artist's songs that the world plays most, and the artist that they were ranked for. It
    /// is nil until the ranking is done. It is empty when fewer than ``ArtistPopular/fewest``
    /// songs can be ranked.
    @State private var popular: (artist: String, songs: [ArtistShelves.ArtistSong])?
    /// Whether the rows under the header have stopped waiting for the ranking.
    @State private var waited = false
    /// Whether the rows were shown without the ranking. A ranking that arrives after the rows is
    /// kept for the next visit. It is not put above rows that are already on the screen, because
    /// that would move them.
    @State private var rowsWithout = false
    /// The Wikipedia article about the artist, and whether the whole article is open.
    @State private var article: EncyclopediaArticle?
    @State private var articleOf: String?
    @State private var reading = false
    /// Whether the artist's photograph set the colour of the room. If it did, the first record's
    /// sleeve does not set it afterwards.
    @State private var photoLit = false

    /// How long the rows under the header wait for the popular tracks on a first visit, so that
    /// the rows appear together with them and do not move down when they arrive.
    static let rowsWait: Duration = .seconds(3)

    /// The photograph's size on the page. ``TVModel/warmArtist(_:scale:)`` fetches this size.
    static let photoEdge: CGFloat = 300

    var body: some View {
        let albums = model.session.albums
        if let artist = Self.find(name, in: read.artists(albums)) {
            let shelves = read.shelves(of: artist, in: albums)
            let songs = shelves.songs.map(\.track)
            // Both values come from memory on the first frame if they were read before, as on the
            // phone's artist page. A page that is opened again is drawn complete at once.
            let ranked = rowsWithout ? [] : popular?.artist == artist.name ? popular?.songs
                : Self.kept(shelves.songs, store: model.worldPlays)
            let about = articleOf == artist.name ? article : model.articles.cached(.artist(artist.name))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 56) {
                    HStack(alignment: .top, spacing: 56) {
                        Portrait(artist: artist.name, edge: Self.photoEdge) { photo in
                            photoLit = true
                            screens.paint(page, Thumbnail.colours(of: photo))
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            Text(artist.name)
                                .font(.tv(64, .bold))
                                .foregroundStyle(Ink.words)
                                .lineLimit(2)
                            Text(Loc.get("Rpm_Library_CountsJoin",
                                         Counts.albums(artist.own.count), Counts.songs(songs.count)))
                                .font(.tv(Size.row))
                                .foregroundStyle(Ink.artist)
                            HStack(spacing: 20) {
                                Button {
                                    model.play(songs, from: 0)
                                    screens.playerShown = true
                                } label: {
                                    Label(Loc.get("Rpm_Artist_PlayAll"), systemImage: "play.fill")
                                }
                                .buttonStyle(.glassProminent)
                                Button {
                                    model.shuffle(songs)
                                    screens.playerShown = true
                                } label: { Image(systemName: "shuffle") }
                                .buttonStyle(.glass)
                            }
                            .padding(.top, 10)
                            // The Wikipedia text, as on the phone's artist page. Space for four
                            // lines is reserved whether or not the text has arrived, so nothing
                            // moves when it does.
                            ZStack(alignment: .topLeading) {
                                Text(verbatim: "1\n2\n3\n4").font(.tv(24)).hidden()
                                if let about, let lead = about.paragraphs.first, !lead.isEmpty {
                                    // The Select button opens the whole article.
                                    Button { reading = true } label: {
                                        Text(Prose.lead(lead, lines: 4, perLine: 90))
                                            .font(.tv(24))
                                            .foregroundStyle(Color.white.opacity(0.75))
                                            .lineLimit(4)
                                            .frame(maxWidth: 1200, alignment: .leading)
                                    }
                                    .buttonStyle(ProseStyle())
                                    .remembered("article")
                                    .transition(.opacity)
                                    .sheet(isPresented: $reading) {
                                        ArticleSheet(heading: Loc.get("TrackInfo_AboutArtist"), name: artist.name, article: about)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, Size.side)
                    .focusSection()

                    if let ranked {
                        if !ranked.isEmpty {
                            SongColumns(heading: Loc.get("Artists_PopularTracks"), space: "popular",
                                        songs: ranked.map { ($0.track, $0.album) })
                        }
                    }

                    if ranked != nil || waited {
                        ForEach(Self.rows(shelves), id: \.title) { row in
                            VStack(alignment: .leading, spacing: 8) {
                                Heading(row.title)
                                CardRow(space: row.title, items: row.albums) { AlbumCard(album: $0) }
                            }
                        }

                        // The playlists and mood playlists that contain the artist's songs, as on
                        // the Android TV app's artist page.
                        let theirs = Set(shelves.songs.map(\.track.rpmId))
                        let holding = model.session.playlists.filter { $0.tracks.contains { theirs.contains($0.rpmId) } }
                        let playlists = holding.filter { $0.origin == .stored }
                        let moods = holding.filter { $0.origin == .generated }
                        if !playlists.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Heading(Loc.get("Artists_InPlaylists"))
                                CardRow(space: "playlists", items: playlists) { ListCard(set: $0) }
                            }
                        }
                        if !moods.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Heading(Loc.get("Genres_MoodPlaylists"))
                                CardRow(space: "moods", items: moods) { ListCard(set: $0) }
                            }
                        }

                        // The related artists in this collection, as on the Android TV app's
                        // artist page.
                        if let related, related.ask == relatedAsk(artist), !related.acts.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Heading(Loc.get("Artists_Related"))
                                CardRow(space: "related", items: related.acts) { act in
                                    ArtistCard(artist: act, edge: 200) { screens.open(.artist(act.name)) }
                                }
                            }
                        }

                        // There is no list of every song. The search finds any song, as in the
                        // Android TV app and on the phone.
                    } else {
                        RecordSpinner(diameter: 56)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
                .padding(.top, Size.belowPill)
                .padding(.bottom, 80)
            }
            .scrollClipDisabled()
            .task(id: artist.name) {
                let subject = ArticleStore.Subject.artist(artist.name)
                let had = model.articles.cached(subject) != nil
                let found = await model.articles.article(subject)
                guard !Task.isCancelled else { return }
                var put = Transaction()
                if !had { put.animation = .easeOut(duration: 0.6) }
                withTransaction(put) {
                    article = found
                    articleOf = artist.name
                }
            }
            .task(id: artist.name) {
                let had = Self.kept(shelves.songs, store: model.worldPlays) != nil
                let songs = await Self.rank(shelves.songs, store: model.worldPlays)
                guard !Task.isCancelled else { return }
                var put = Transaction()
                if !had { put.animation = .easeOut(duration: 0.3) }
                withTransaction(put) { popular = (artist.name, songs) }
            }
            .task(id: artist.name) {
                try? await Task.sleep(for: Self.rowsWait)
                guard !Task.isCancelled else { return }
                let ranked = popular?.artist == artist.name || Self.kept(shelves.songs, store: model.worldPlays) != nil
                withAnimation(.easeOut(duration: 0.3)) {
                    rowsWithout = !ranked
                    waited = true
                }
            }
            .task(id: relatedAsk(artist)) {
                // Run off the main thread, because the rule reads every track of the collection.
                let ask = relatedAsk(artist)
                let from = relatedFrom()
                let acts = await Task.detached(priority: .utility) { RelatedArtists.of(ask.artist, in: from) }.value
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { related = (ask, acts) }
            }
            .task(id: artist.name) {
                // The room takes its colour from the first record's sleeve while there is no
                // photograph, as in the Android TV app. When the photograph arrives, it sets the
                // colour instead.
                guard let first = shelves.records.first ?? shelves.songs.first?.album else { return }
                let art = await model.artwork.cover(for: first, on: model.session.shelves.shelf(ofAlbum: first), edge: 128)
                guard !Task.isCancelled, !photoLit, let art else { return }
                screens.paint(page, art.colours)
            }
        } else {
            Message(Loc.get("Artists_Empty"))
        }
    }

    /// The ranking from the data that the store already holds, if it holds an answer for every
    /// record, as in the phone's `popularKept`. Otherwise nil, because a ranking from only some of
    /// the records would be replaced by a different ranking when the rest arrive.
    @MainActor
    static func kept(_ songs: [ArtistShelves.ArtistSong], store: WorldPlays) -> [ArtistShelves.ArtistSong]? {
        PopularPlays.cached(ArtistPopular.records(songs), store: store)
            .map { ArtistPopular.ranked(songs, plays: $0) }
    }

    /// Ranks the artist's songs by how often the world plays them, as in the phone's
    /// `rankPopular`.
    @MainActor
    static func rank(_ songs: [ArtistShelves.ArtistSong], store: WorldPlays) async -> [ArtistShelves.ArtistSong] {
        ArtistPopular.ranked(songs, plays: await PopularPlays.ask(ArtistPopular.records(songs), store: store))
    }

    /// The artist that a name opens: the artist with that name. For a credit that names several
    /// artists ("A & B", from a record or the player), it is the first of them, because the
    /// artists list files the record under the first.
    static func find(_ name: String, in artists: [ArtistWallItem]) -> ArtistWallItem? {
        func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        if let exact = artists.first(where: { same($0.name, name) }) { return exact }
        guard let first = ArtistCredit.first(name) else { return nil }
        return artists.first { same($0.name, first) }
    }

    private struct Row { let title: String; let albums: [CloudAlbum] }

    /// The input that the related artists are read for: the artist as the wall holds it, and the
    /// size of the data that they are read from. A library change that adds or removes a record,
    /// an artist or a list causes them to be read again.
    struct RelatedAsk: Equatable {
        let artist: ArtistWallItem
        let acts: Int
        let albums: Int
        let lists: Int
    }

    private func relatedAsk(_ artist: ArtistWallItem) -> RelatedAsk {
        let albums = model.session.albums
        return RelatedAsk(artist: artist, acts: read.artists(albums).count, albums: albums.count,
                          lists: model.session.playlists.count)
    }

    /// Every artist, the genre shelves, the records by key and the tracks of every list.
    private func relatedFrom() -> RelatedArtists.Collection {
        let albums = model.session.albums
        return RelatedArtists.Collection(artists: read.artists(albums), genres: readGenres.genres(albums),
                                         albums: read.albums(albums),
                                         lists: model.session.playlists.map(\.tracks))
    }

    private static func rows(_ shelves: ArtistShelves) -> [Row] {
        [Row(title: Loc.get("Artists_Albums"), albums: shelves.records),
         Row(title: Loc.get("Artists_Collaborations"), albums: shelves.together),
         Row(title: Loc.get("Artists_LiveAlbums"), albums: shelves.live),
         Row(title: Loc.get("Artists_Soundtracks"), albums: shelves.soundtracks),
         Row(title: Loc.get("Artists_Compilations"), albums: shelves.compilations),
         Row(title: Loc.get("Artists_Singles"), albums: shelves.singles),
         Row(title: Loc.get("Artists_AppearsOn"), albums: shelves.appearances)]
            .filter { !$0.albums.isEmpty }
    }
}

// MARK: Genres

/// The genres list: each genre has its own lettering on a room in the genre's colour.
struct GenresView: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    @State private var read = ReadGenres()

    var body: some View {
        let genres = read.genres(model.session.albums)

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                PageBar(genres.count == 1 ? Loc.get("Genres_CountOne") : Loc.get("Genres_Count", String(genres.count)))

                if genres.isEmpty {
                    Message(Loc.get("Genres_Empty")).frame(height: 400)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(GenreCard.width), spacing: Card.gap),
                                             count: GenreCard.columns),
                              alignment: .leading, spacing: 56) {
                        ForEach(genres) { genre in
                            GenreCard(name: genre.name) { screens.open(.genre(genre.name)) }
                        }
                    }
                    .padding(.horizontal, Size.side)
                }
            }
            .padding(.top, Size.top)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
    }
}

/// A genre card: the desktop app's photograph for the genre under the genre's colour, or the room
/// if the genre has no photograph, with the lettering over it. There is no name or count under
/// the card, as in the Android TV app, because the lettering spells the name.
struct GenreCard: View {
    static let columns = 4
    static let width = Card.wide

    /// The opacity of the genre's dark tone over the photograph, so that the white lettering can be
    /// read on any part of it. Matches `PHOTO_SHADE` in the Android TV app.
    static let photoShade = 0.55

    let name: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .bottomLeading) {
                if GenrePhotos.has(name) {
                    let shade = Self.shade(name)
                    shade
                    GenrePhoto(genre: name, width: Self.width)
                    shade.opacity(Self.photoShade)
                } else {
                    StationRoom(colours: GenreColours.of(name), breathes: false, seed: name)
                }
                GenreLettering(genre: name)
                    .frame(width: Self.width - 80, height: 110, alignment: .bottomLeading)
                    .padding(24)
            }
            .frame(width: Self.width, height: Self.width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .hoverEffect(.highlight)
            .accessibilityLabel(name)
        }
        .buttonStyle(.borderless)
        .remembered("genre:" + name)
    }

    /// The genre's colour reduced to a dark tone. The photograph is drawn on this background.
    static func shade(_ genre: String) -> Color {
        guard let rgb = GenreMarks.colour(genre) else { return Color.black }
        return Color(red: Double(rgb.r) / 255 * 0.35, green: Double(rgb.g) / 255 * 0.35,
                     blue: Double(rgb.b) / 255 * 0.35)
    }
}

/// The number of listens that the world has for the songs on a page. Each record is requested once.
/// Four requests run at a time, and the next request starts when one finishes (as in the phone's
/// `rankPopular`). The values can also be read from what the store already holds.
enum PopularPlays {
    /// The listens of every record, if the store holds an answer for every record. Otherwise nil.
    @MainActor
    static func cached(_ records: [CloudAlbum], store: WorldPlays) -> [String: [TrackPlace: Int64]]? {
        var plays: [String: [TrackPlace: Int64]] = [:]
        for record in records {
            guard let known = store.cached(WorldPlays.Record(record)) else { return nil }
            plays[record.key] = known
        }
        return plays
    }

    /// The listens of every record that answered. A record that could not be requested adds
    /// nothing this time.
    @MainActor
    static func ask(_ records: [CloudAlbum], store: WorldPlays) async -> [String: [TrackPlace: Int64]] {
        await withTaskGroup(of: (String, [TrackPlace: Int64]?).self,
                            returning: [String: [TrackPlace: Int64]].self) { group in
            var plays: [String: [TrackPlace: Int64]] = [:]
            var next = 0

            // Start four requests, then one more each time a request finishes.
            while next < records.count {
                if next >= 4, let (key, answer) = await group.next() {
                    if let answer { plays[key] = answer }
                }

                let key = records[next].key
                let asked = WorldPlays.Record(records[next])
                next += 1
                group.addTask { (key, await store.plays(asked)) }
            }

            for await (key, answer) in group {
                if let answer { plays[key] = answer }
            }
            return plays
        }
    }
}

/// How much music the Play all and Shuffle buttons of a genre use. Matches `GenrePage.kt` in the
/// Android TV app.
enum GenrePlay {
    /// Play all: the newest records, played completely.
    static let newestRecords = 10
    /// Shuffle: songs are taken from this many records, chosen at random...
    static let shuffleRecords = 40
    /// ...and at most this many songs are used.
    static let shuffleSongs = 200
}

/// A section of songs, such as an artist's popular tracks or a genre's most played songs. It has
/// a heading with a Play all button beside it, then the songs in two columns. Each row plays the
/// section starting from that song.
private struct SongColumns: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let heading: String
    let space: String
    let songs: [(track: CloudTrack, album: CloudAlbum?)]

    var body: some View {
        let tracks = songs.map(\.track)
        let half = (songs.count + 1) / 2
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(heading)
                    .font(.tv(Size.heading, .semibold))
                    .foregroundStyle(Ink.card)
                Spacer()
                Button(Loc.get("Home_PlayAllTracks"), systemImage: "play.fill") {
                    model.play(tracks, from: 0)
                    screens.playerShown = true
                }
                .buttonStyle(.glass)
                .remembered(space + ".playAll")
            }
            .padding(.horizontal, Size.side)

            HStack(alignment: .top, spacing: Card.gap) {
                ForEach([0, 1], id: \.self) { column in
                    let range = column == 0 ? 0..<half : half..<songs.count
                    VStack(spacing: 6) {
                        ForEach(range, id: \.self) { at in
                            TrackRow(track: songs[at].track, number: at + 1, album: songs[at].album,
                                     line: .artistAndAlbum, queue: tracks, at: at)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, Size.side - RowStyle.inset)
            .focusSection()
        }
    }
}

/// A genre's colour in the form of a sleeve's colours, so that a room can use it.
enum GenreColours {
    @MainActor
    static func of(_ genre: String) -> SleeveColours? {
        guard let rgb = GenreMarks.colour(genre) else { return nil }
        return SleeveColours(accent: nil, dominant: rgb, highlight: rgb, shade: nil)
    }
}

/// A genre's page, laid out like the artist page in the Android TV app. The top shows the genre's
/// lettering and the start of its English Wikipedia article, beside the desktop app's photograph
/// for the genre. Below are the popular songs of the genre, the listener's most played songs of
/// it, its notable artists, its Made for you lists, its newest records, the related genres, its
/// records by decade and all its records. If the genre has no article, the page shows the number
/// of records and artists instead. The room takes the genre's colour.
struct GenrePage: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let name: String
    let page: Page
    @State private var read = ReadGenres()
    @State private var readArtists = ReadArtists()
    /// The popular songs of the genre, and the genre that they were ranked for. It is nil until the
    /// ranking is done. It is empty when fewer than ``ArtistPopular/fewest`` songs can be ranked.
    @State private var popular: (genre: String, songs: [ArtistShelves.ArtistSong])?
    /// Whether the rows under the header have stopped waiting for the ranking, as on the artist
    /// page.
    @State private var waited = false
    /// Whether the rows were shown without the ranking. A ranking that arrives after the rows is
    /// kept for the next visit and is not put above rows that are already on the screen.
    @State private var rowsWithout = false
    /// The Wikipedia article about the genre, and whether the whole article is open.
    @State private var article: EncyclopediaArticle?
    @State private var articleOf: String?
    @State private var reading = false

    /// The width of the photograph on the page.
    private static let photoWidth: CGFloat = 760

    var body: some View {
        let albums = model.session.albums
        let byKey = readArtists.albums(albums)
        if let shelves = read.shelves(of: name, in: albums, byKey: byKey, artists: readArtists.artists(albums)) {
            let records = shelves.albums.compactMap { byKey[$0] }
            let moods = model.session.playlists.filter {
                $0.origin == .generated && $0.cut?.genre == name && $0.cut?.decade == 0
            }
            let spoken = Genres.spoken(name)
            let asked = Self.asked(records, played: model.session.played)
            let ranked = rowsWithout ? [] : popular?.genre == name ? popular?.songs
                : Self.kept(asked, store: model.worldPlays)
            let about = articleOf == name ? article : model.articles.cached(.genre(name))

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 56) {
                    HStack(alignment: .top, spacing: 56) {
                        VStack(alignment: .leading, spacing: 24) {
                            GenreLettering(genre: name)
                                .frame(width: 820, height: 150, alignment: .bottomLeading)
                            // The start of the article. Space for four lines is reserved whether
                            // or not the text has arrived, so nothing moves when it does. If there
                            // is no article, the counts are shown instead.
                            ZStack(alignment: .topLeading) {
                                Text(verbatim: "1\n2\n3\n4").font(.tv(24)).hidden()
                                if let about, let lead = about.paragraphs.first, !lead.isEmpty {
                                    Button { reading = true } label: {
                                        Text(Prose.lead(lead, lines: 4, perLine: 70))
                                            .font(.tv(24))
                                            .foregroundStyle(Color.white.opacity(0.75))
                                            .lineLimit(4)
                                            .frame(maxWidth: 900, alignment: .leading)
                                    }
                                    .buttonStyle(ProseStyle())
                                    .remembered("article")
                                    .transition(.opacity)
                                    .sheet(isPresented: $reading) {
                                        ArticleSheet(heading: Loc.get("Genres_About"), name: name, article: about)
                                    }
                                } else if articleOf == name {
                                    // Each count has its own singular form ("1 album, 1 artist").
                                    Text(Loc.get("Rpm_Library_CountsJoin", Counts.albums(shelves.albums.count),
                                                 shelves.actCount == 1 ? Loc.get("Artists_CountOne")
                                                                       : Loc.get("Artists_Count", String(shelves.actCount))))
                                        .font(.tv(Size.row))
                                        .foregroundStyle(Ink.artist)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        if GenrePhotos.has(name) {
                            GenrePhoto(genre: name, width: Self.photoWidth)
                                .frame(width: Self.photoWidth, height: Self.photoWidth / GenrePhotos.shape)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, Size.side)
                    .focusSection()

                    if let ranked, !ranked.isEmpty {
                        SongColumns(heading: Loc.get("Genres_PopularTracks"), space: "popular",
                                    songs: ranked.map { ($0.track, $0.album) })
                    }

                    if ranked != nil || waited {
                        rows(shelves: shelves, records: records, byKey: byKey, moods: moods, spoken: spoken)
                    } else {
                        RecordSpinner(diameter: 56)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
                .padding(.top, Size.belowPill)
                .padding(.bottom, 80)
            }
            .scrollClipDisabled()
            .onAppear {
                if let colours = GenreColours.of(name) { screens.paint(page, colours) }
            }
            .task(id: name) {
                let subject = ArticleStore.Subject.genre(name)
                let had = model.articles.cached(subject) != nil
                let found = await model.articles.article(subject)
                guard !Task.isCancelled else { return }
                var put = Transaction()
                if !had { put.animation = .easeOut(duration: 0.6) }
                withTransaction(put) {
                    article = found
                    articleOf = name
                }
            }
            .task(id: name) {
                let had = Self.kept(asked, store: model.worldPlays) != nil
                let plays = await PopularPlays.ask(asked, store: model.worldPlays)
                guard !Task.isCancelled else { return }
                let songs = GenrePopular.ranked(GenrePopular.songs(asked), plays: plays)
                var put = Transaction()
                if !had { put.animation = .easeOut(duration: 0.3) }
                withTransaction(put) { popular = (name, songs) }
            }
            .task(id: name) {
                try? await Task.sleep(for: ArtistPage.rowsWait)
                guard !Task.isCancelled else { return }
                let ranked = popular?.genre == name || Self.kept(asked, store: model.worldPlays) != nil
                withAnimation(.easeOut(duration: 0.3)) {
                    rowsWithout = !ranked
                    waited = true
                }
            }
        } else {
            Message(Loc.get("Genres_Empty"))
        }
    }

    /// All the content under the popular songs.
    @ViewBuilder
    private func rows(shelves: GenreShelves, records: [CloudAlbum], byKey: [String: CloudAlbum],
                      moods: [PlaylistSet], spoken: String) -> some View {
        // The listener's most played songs of the genre, as on the phone's genre page.
        let byId = Dictionary(records.flatMap(\.tracks).map { ($0.rpmId, $0) },
                              uniquingKeysWith: { first, _ in first })
        let heard = HomeSongs.mostPlayed(records, played: model.session.played, count: 10)
            .compactMap { byId[$0] }
        if !heard.isEmpty {
            SongColumns(heading: Loc.get("Genres_YourMostPlayed", spoken), space: "heard",
                        songs: heard.map { ($0, byKey[AlbumGrouping.key(for: $0)]) })
        }

        if !shelves.acts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Heading(Loc.get("Genres_NotableArtists", spoken))
                CardRow(space: "acts", items: shelves.acts) { artist in
                    ArtistCard(artist: artist, edge: 200) { screens.open(.artist(artist.name)) }
                }
            }
        }
        if !moods.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Heading(Loc.get("Home_MadeForYou"))
                CardRow(space: "moods", items: moods) { ListCard(set: $0) }
            }
        }
        let added = shelves.added.compactMap { byKey[$0] }
        if !added.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Heading(Loc.get("Genres_RecentlyAdded", spoken))
                CardRow(space: "added", items: added) { AlbumCard(album: $0) }
            }
        }
        if !shelves.related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Heading(Loc.get("Genres_Subgenres"))
                CardRow(space: "related", items: shelves.related.map { RelatedGenre(name: $0.genre) }) { related in
                    GenreCard(name: related.name) { screens.open(.genre(related.name)) }
                }
            }
        }
        ForEach(shelves.eras.reversed(), id: \.decade) { era in
            let records = era.albums.compactMap { byKey[$0] }
            if !records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Heading(Loc.get("Genres_Decade", String(era.decade)))
                    CardRow(space: "decade:\(era.decade)", items: records) { AlbumCard(album: $0) }
                }
            }
        }
        // All the records of the genre, as at the end of the phone's genre page.
        if records.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Heading(Loc.get("Artists_Albums"))
                AlbumGrid(albums: records)
                    .focusSection()
            }
        }
    }

    /// The records whose listens are requested, with the records that this account played most
    /// first (``GenrePopular/records(_:playsOf:)``).
    static func asked(_ records: [CloudAlbum], played: [String: PlayLog.Played]) -> [CloudAlbum] {
        GenrePopular.records(records) { album in
            album.tracks.reduce(0) { $0 + (played[$1.rpmId]?.plays ?? 0) }
        }
    }

    /// The ranking from the data that the store already holds, if it holds an answer for every
    /// record that was requested. Otherwise nil.
    @MainActor
    static func kept(_ asked: [CloudAlbum], store: WorldPlays) -> [ArtistShelves.ArtistSong]? {
        PopularPlays.cached(asked, store: store).map { GenrePopular.ranked(GenrePopular.songs(asked), plays: $0) }
    }
}

private struct RelatedGenre: Identifiable {
    let name: String
    var id: String { name }
}
