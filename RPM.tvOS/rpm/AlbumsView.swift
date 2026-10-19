import SwiftUI
import RPMKit
import RPMLibrary
import RPMSession

/// The album wall: every record in six columns, or the carousel, with the grid or carousel key, the
/// order key and the favourites key at the top right. The order key offers the five orders; the
/// favourites key shows only the records holding a favourite song, on the account's own collection
/// (a borrowed one's hearts are its owner's).
struct AlbumsView: View {
    @Environment(TVModel.self) private var model
    @AppStorage("tv.wall.order") private var orderName = AlbumOrdering.artist.rawValue
    @State private var favouritesOnly = false
    /// The record in front of the carousel. It is kept while this screen exists, so Back from a
    /// record returns to it.
    @State private var carouselFront = 0

    private var order: AlbumOrdering { AlbumOrdering(rawValue: orderName) ?? .artist }

    var body: some View {
        let session = model.session
        let own = session.viewing.isOwn
        let shown = Wall.of(session.albums, order: order, favouritesOnly: favouritesOnly && own,
                            played: session.played, marked: { session.isTrackMarked($0) })

        if model.settings.albumCarousel, !shown.isEmpty {
            ZStack(alignment: .top) {
                AlbumCarousel(albums: shown, order: order, front: $carouselFront)
                bar(shown, own: own)
                    .padding(.top, Size.top)
            }
        } else {
            grid(shown, own: own)
        }
    }

    private func grid(_ shown: [CloudAlbum], own: Bool) -> some View {
        let session = model.session
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 30) {
                bar(shown, own: own)

                if shown.isEmpty {
                    Message(session.albums.isEmpty ? Loc.get("Tv_Library_Empty") : Loc.get("Viz_LibraryNoMatch"))
                        .frame(height: 400)
                } else {
                    AlbumGrid(albums: shown)
                }
            }
            .padding(.top, Size.top)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
    }

    /// The count, the order key and the favourites key.
    private func bar(_ shown: [CloudAlbum], own: Bool) -> some View {
                PageBar(Counts.albums(shown.count)) {
                    // Grid or carousel, here as in Settings. The key shows the view that it
                    // switches to.
                    let carousel = model.settings.albumCarousel
                    Button {
                        model.settings.switchAlbumView()
                    } label: {
                        Image(systemName: carousel ? "square.grid.3x3" : "rectangle.stack")
                    }
                    .buttonStyle(.glass)
                    .remembered("view")
                    .accessibilityLabel(carousel ? Loc.get("Tv_AlbumViewGrid") : Loc.get("Tv_AlbumViewCarousel"))
                    Menu {
                        Picker(Loc.get("AlbumSort_Tooltip"), selection: $orderName) {
                            ForEach(AlbumOrdering.allCases, id: \.self) { ordering in
                                Text(Wall.label(ordering)).tag(ordering.rawValue)
                            }
                        }
                    } label: {
                        Label(Wall.label(order), systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.glass)
                    .remembered("order")
                    if own {
                        Button {
                            favouritesOnly.toggle()
                        } label: {
                            Image(systemName: favouritesOnly ? "heart.fill" : "heart")
                                .keyTint(favouritesOnly ? Ink.loved : nil)
                        }
                        .buttonStyle(.glass)
                        .remembered("favourites")
                    }
                }
    }
}

/// Records in six columns, which is how many the Android TV app shows for viewing from a sofa.
/// The columns use the cards and gaps of the home rows, so a record is in the same place on both.
struct AlbumGrid: View {
    let albums: [CloudAlbum]

    static let columns = 6

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Card.edge), spacing: Card.gap), count: Self.columns),
                  alignment: .leading, spacing: 56) {
            ForEach(albums) { AlbumCard(album: $0, edge: Card.edge) }
        }
        .padding(.horizontal, Size.side)
    }
}

/// The wall as it is drawn: narrowed to favourites if asked, and in an order.
enum Wall {
    static func of(_ albums: [CloudAlbum], order: AlbumOrdering, favouritesOnly: Bool,
                   played: [String: PlayLog.Played], marked: (CloudTrack) -> Bool) -> [CloudAlbum] {
        let narrowed = favouritesOnly ? albums.filter { $0.tracks.contains(where: marked) } : albums
        return AlbumSort.by(narrowed, order) { album in
            AlbumFacts(album: album.album, artist: album.artist,
                       addedAt: AlbumSort.addedOf(album.tracks),
                       year: AlbumSort.yearOf(album.tracks),
                       plays: album.tracks.reduce(0) { $0 + (played[$1.rpmId]?.plays ?? 0) })
        }
    }

    static func label(_ order: AlbumOrdering) -> String {
        switch order {
        case .artist: Loc.get("AlbumSort_Artist")
        case .album: Loc.get("AlbumSort_Album")
        case .added: Loc.get("AlbumSort_Added")
        case .year: Loc.get("AlbumSort_Year")
        case .plays: Loc.get("AlbumSort_Plays")
        }
    }
}

/// The Search item of the side menu: albums whose name or artist contains the typed text, and the
/// songs that match, in the search screen of tvOS with its keyboard.
struct SearchView: View {
    @State private var asked = ""

    var body: some View {
        SearchResults(asked: asked)
            .searchable(text: $asked, prompt: Loc.get("Viz_BrowseSearch"))
    }
}

/// What a search found: the records, then the songs.
private struct SearchResults: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let asked: String
    @State private var readArtists = ReadArtists()

    var body: some View {
        let albums = model.session.albums
        let records = SongSearch.records(albums, for: asked)
        let songs = Array(SongSearch.through(albums, for: asked).prefix(60))
        // The artists whose name contains the typed text, normalised in the same way as the phone's
        // artist search.
        let wanted = ArtistWall.searchKey(asked)
        let artists = wanted.isEmpty ? [] : readArtists.artists(albums).filter { ArtistWall.searchKey($0.name).contains(wanted) }

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 50) {
                if !asked.trimmingCharacters(in: .whitespaces).isEmpty {
                    if records.isEmpty, songs.isEmpty, artists.isEmpty {
                        Message(Loc.get("Viz_LibraryNoMatch")).frame(height: 300)
                    }
                    if !artists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Heading(Loc.get("Viz_MenuArtists"))
                            CardRow(space: "artists", items: artists) { artist in
                                ArtistCard(artist: artist, edge: 200) { screens.open(.artist(artist.name)) }
                            }
                        }
                    }
                    if !records.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Heading(Loc.get("Viz_MenuAlbums"))
                            CardRow(space: "records", items: records) { AlbumCard(album: $0) }
                        }
                    }
                    if !songs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Heading(Loc.get("Album_Tracks"))
                            VStack(spacing: 6) {
                                ForEach(songs) { hit in
                                    // The queue is the song's record, so playback does not stop after
                                    // one song (the same as the phone's `play(_ track:)`).
                                    let at = hit.album.tracks.firstIndex { $0.rpmId == hit.track.rpmId }
                                    TrackRow(track: hit.track, number: nil, album: hit.album, line: .artistAndAlbum,
                                             queue: at == nil ? [hit.track] : hit.album.tracks, at: at ?? 0)
                                }
                            }
                            .padding(.horizontal, Size.side)
                            .focusSection()
                        }
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        // The search screen insets its content under the keyboard by the screen's margin. The rows
        // keep their own margin, so they line up with the rows of every other screen.
        .ignoresSafeArea(.container, edges: .horizontal)
    }
}
