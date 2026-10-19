import SwiftUI
import RPMSharedUI
import UIKit
import RPMKit
import RPMLibrary
import RPMDesign

// ── the photograph ──
// The lettering is GenreLettering, in RPMSharedUI.

/// What each genre looks like: its lettering, its colour and its photograph. Each is read once
/// and kept.
@MainActor
enum GenreLooks {
    /// `NSCache` does its own eviction and its operations are atomic; see ``SmallPicture``.
    private nonisolated(unsafe) static let photos = NSCache<NSString, UIImage>()

    static func mark(_ genre: String) -> GenreWordmark? { GenreMarks.mark(genre) }

    static func outline(_ mark: GenreWordmark) -> CGPath { GenreMarks.outline(mark) }

    /// The genre's colour, from the app's palette. For a genre with no lettering it is the ground
    /// colour, but every genre on the wall has lettering.
    static func colour(_ genre: String) -> Color {
        guard let rgb = GenreMarks.colour(genre) else { return RPMInk.ground }
        return Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    /// The genre's portrait photograph, made by `scripts/gen_genre_photos_phone.py`. The file
    /// name uses the same slug as the desktop's photographs: lower case, with every run of
    /// characters that are not letters or digits replaced by one hyphen.
    static func photo(_ genre: String) -> UIImage? {
        let name = "genre-" + slug(genre)
        if let held = photos.object(forKey: name as NSString) { return held }
        guard let url = Bundle.module.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        photos.setObject(image, forKey: name as NSString)
        return image
    }

    private static func slug(_ name: String) -> String {
        var out = ""
        var gap = false
        for character in name.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if gap && !out.isEmpty { out.append("-") }
                out.append(character)
                gap = false
            } else {
                gap = true
            }
        }
        return out
    }
}

/// A genre's photograph, filling its box. The genre's colour fades in from the bottom so the
/// lettering is easy to read.
private struct GenrePicture: View {
    let genre: String

    var body: some View {
        let colour = GenreLooks.colour(genre)

        ZStack {
            colour

            if let photo = GenreLooks.photo(genre) {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            LinearGradient(stops: [.init(color: colour.opacity(0), location: 0.35),
                                   .init(color: colour.opacity(0.6), location: 0.72),
                                   .init(color: colour.opacity(0.92), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// ── the wall ──

/// One genre on the wall: a portrait card with its photograph, its name in its own lettering at
/// the bottom, and the number of albums.
private struct GenreCard: View {
    let genre: String
    let albums: Int

    /// The height of the lettering. The wall's cards and the smaller cards on the page use
    /// different values.
    var lettering: Double = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .background { GenrePicture(genre: genre) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    GenreLettering(genre: genre)
                        .frame(height: lettering)

                    Text(albumCount(albums))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RPMInk.white(0xCC / 255))
                }
                .padding(12)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
            .contentShape(shape)
    }
}

private func albumCount(_ count: Int) -> String {
    count == 1 ? Loc.get("Stats_AlbumsOne") : Loc.get("Stats_Albums", count)
}

/// The collection grouped by kind of music: one portrait card per genre.
///
/// This is the phone version of the desktop's genres wall. The genres, lettering, colours and
/// photographs come from the desktop. The cards are portrait and two across, because the phone
/// is held upright. ``GenreWall`` decides which genre a record belongs to, and its tests check
/// that it gives the same answers as the desktop.
public struct GenresPage: View {
    public typealias Standing = LibraryPage.Standing

    private let genres: [GenreWallItem]
    private let standing: Standing
    private let lender: String?
    private let onOpen: (GenreWallItem) -> Void
    private let onRefresh: () async -> Void

    @Binding private var mode: LibraryMode

    public init(genres: [GenreWallItem], standing: Standing, mode: Binding<LibraryMode>,
                lender: String?, onOpen: @escaping (GenreWallItem) -> Void,
                onRefresh: @escaping () async -> Void) {
        self.genres = genres
        self.standing = standing
        _mode = mode
        self.lender = lender
        self.onOpen = onOpen
        self.onRefresh = onRefresh
    }

    private static let gutter: Double = 14

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                switch standing {
                case .reading: waiting
                case .trouble(let said): failed(said)
                case .showing: wall
                }
            }
            .frame(maxHeight: .infinity)
            .scrollsUnder {
                VStack(spacing: 0) {
                    header
                    LibraryModeTabs($mode)
                }
            }
        }
        .background { VinylGround() }
    }

    private var header: some View {
        PageHeading(Loc.get("Genres_Title"), line: counts) { EmptyView() }
            .padding(.leading, RPMLayout.margin)
            .padding(.trailing, 16)
            .padding(.bottom, 10)
    }

    private var counts: String {
        genres.count == 1 ? Loc.get("Genres_CountOne") : Loc.get("Genres_Count", genres.count)
    }

    @ViewBuilder
    private var wall: some View {
        if genres.isEmpty {
            empty
        } else {
            DissolvingScroll {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.gutter),
                                    GridItem(.flexible(), spacing: Self.gutter)],
                          spacing: Self.gutter) {
                    ForEach(genres) { item in
                        Button { onOpen(item) } label: {
                            GenreCard(genre: item.name, albums: item.albums.count)
                        }
                            .buttonStyle(RowPress())
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.top, 4)
                .padding(.bottom, RPMLayout.foot)
            }
            .scrollIndicators(.hidden)
            .refreshable { await onRefresh() }
        }
    }

    private var empty: some View {
        Text(Loc.get(lender == nil ? "Genres_Empty" : "Rpm_Share_EmptyShelf"))
            .font(RPMFont.display(14))
            .foregroundStyle(RPMInk.white(0x88 / 255))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            RecordSpinner(diameter: 96)

            Text(Loc.get("Rpm_Library_Loading"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
}

// ── one genre ──

/// One genre's page. At the top is its photograph, which runs up behind the clock, with the
/// name in its lettering. Below are its newest records, the listener's most played songs of the
/// genre, the artists with the most records in it, the generated mood lists for it, related
/// genres, its records by decade, and a wall of all its records. ``GenreShelves`` builds the
/// shelves from the collection.
public struct GenrePage: View {
    private let genre: String
    private let shelves: GenreShelves
    private let albums: [String: CloudAlbum]

    /// The listener's most played songs of the genre, most played first. Empty until a song of
    /// the genre has been played.
    private let mostPlayed: [CloudTrack]

    /// The generated mood lists for this genre, in the order they were received.
    private let moods: [PlaylistSet]

    private let covers: any CoverStore
    private let onOpen: (CloudAlbum) -> Void
    private let onPlay: ([CloudTrack]) -> Void
    private let onArtist: (ArtistWallItem) -> Void
    private let onList: (PlaylistSet) -> Void
    private let onGenre: (String) -> Void
    private let onBack: () -> Void

    /// The long-press menu on the most played songs. See ``HomePicksRow/songMenu``.
    private let songMenu: TrackMenu

    public init(genre: String, shelves: GenreShelves, albums: [String: CloudAlbum],
                mostPlayed: [CloudTrack], moods: [PlaylistSet], covers: any CoverStore,
                onOpen: @escaping (CloudAlbum) -> Void,
                onPlay: @escaping ([CloudTrack]) -> Void,
                onArtist: @escaping (ArtistWallItem) -> Void,
                onList: @escaping (PlaylistSet) -> Void,
                onGenre: @escaping (String) -> Void,
                onBack: @escaping () -> Void,
                songMenu: TrackMenu) {
        self.songMenu = songMenu
        self.genre = genre
        self.shelves = shelves
        self.albums = albums
        self.mostPlayed = mostPlayed
        self.moods = moods
        self.covers = covers
        self.onOpen = onOpen
        self.onPlay = onPlay
        self.onArtist = onArtist
        self.onList = onList
        self.onGenre = onGenre
        self.onBack = onBack
    }

    /// The head's height as a fraction of the screen width, not counting the status bar.
    private static let headShape: Double = 0.85

    private var spoken: String { Genres.spoken(genre) }

    private func records(_ keys: [String]) -> [CloudAlbum] { keys.compactMap { albums[$0] } }

    public var body: some View {
        GeometryReader { geometry in
            // Starts at the top of the screen, like home: the photograph runs up behind the
            // clock, and content that scrolls up behind the clock is blurred.
            DissolvingScroll(under: RPMSafeArea.top) {
                VStack(alignment: .leading, spacing: 26) {
                    head(width: geometry.size.width)

                    if !shelves.added.isEmpty {
                        HomeRowView(heading: Loc.get("Genres_RecentlyAdded", spoken),
                                    albums: records(shelves.added), covers: covers, onOpen: onOpen)
                    }

                    if !mostPlayed.isEmpty {
                        HomePicksRow(heading: Loc.get("Genres_YourMostPlayed", spoken),
                                     picks: mostPlayed.map { QuickPick(kind: .song, key: $0.rpmId) },
                                     albums: albums,
                                     songs: Dictionary(mostPlayed.map { ($0.rpmId, $0) },
                                                       uniquingKeysWith: { first, _ in first }),
                                     lists: [:], stations: [:], covers: covers,
                                     songLine: .artist,
                                     onOpen: onOpen,
                                     onOpenList: { _ in }, onPlay: onPlay, onTune: { _ in },
                                     songMenu: songMenu)
                    }

                    if !shelves.acts.isEmpty { acts }

                    if !moods.isEmpty {
                        HomeListsRow(heading: Loc.get("Genres_MoodPlaylists"),
                                     names: moods.map(\.name),
                                     lists: Dictionary(moods.map { ($0.name, $0) },
                                                       uniquingKeysWith: { first, _ in first }),
                                     covers: covers,
                                     onOpen: { name in
                                         if let list = moods.first(where: { $0.name == name }) { onList(list) }
                                     })
                    }

                    if !shelves.related.isEmpty { related }

                    if !shelves.eras.isEmpty { eras }

                    wall(width: geometry.size.width)
                }
                .padding(.bottom, RPMLayout.foot)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .background { VinylGround() }
        .rpmFloatingBack(RPMBackKey(label: Loc.get("Album_Back"), action: onBack))
    }

    private func head(width: Double) -> some View {
        let tall = width * Self.headShape + RPMSafeArea.top

        return GenrePicture(genre: genre)
            .frame(width: width, height: tall)
            .clipped()
            // Fades into the page's own ground at the bottom, so the content below does not
            // start at a sharp edge.
            .overlay {
                LinearGradient(stops: [.init(color: RPMInk.ground.opacity(0), location: 0.7),
                                       .init(color: RPMInk.ground.opacity(0.85), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    GenreLettering(genre: genre)
                        .frame(height: 52)

                    Text(Loc.get("Genres_InLibrary", shelves.albums.count, shelves.actCount))
                        .rpmKicker()
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.bottom, 8)
            }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(RPMFont.display(19))
            .padding(.horizontal, RPMLayout.margin)
    }

    /// The artists with the most records in the genre. They use the artists wall's boxes, which
    /// open the same page.
    private var acts: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(Loc.get("Genres_NotableArtists", spoken))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(shelves.acts) { artist in
                        ArtistBox(artist: artist, width: 200,
                                  first: albums[artist.own.first ?? ""], covers: covers)
                            .onTapGesture { onArtist(artist) }
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
            }
        }
    }

    /// The related genres that the collection holds, as small cards that open them.
    private var related: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(Loc.get("Genres_Subgenres"))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(shelves.related, id: \.genre) { relation in
                        Button { onGenre(relation.genre) } label: {
                            GenreCard(genre: relation.genre, albums: relation.albums, lettering: 20)
                                .frame(width: 120)
                        }
                        .buttonStyle(RowPress())
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
            }
        }
    }

    /// The genre's records by decade: one row per decade, oldest first.
    private var eras: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(Loc.get("Genres_Eras", spoken))

            ForEach(shelves.eras, id: \.decade) { era in
                HomeRowView(heading: Loc.get("Genres_Decade", era.decade),
                            albums: records(era.albums), covers: covers, onOpen: onOpen)
            }
        }
    }

    /// All of the genre's records.
    private func wall(width: Double) -> some View {
        let (columns, art) = WallLayout.wall(
            available: width, targetStride: 194,
            edge: AlbumWall.edge, gutter: AlbumWall.gutter,
            maxColumns: AlbumWall.maxColumns, minColumns: AlbumWall.minColumns)

        return VStack(alignment: .leading, spacing: 10) {
            heading(Loc.get("Artists_Albums"))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AlbumWall.gutter),
                                     count: columns),
                      spacing: 0) {
                ForEach(records(shelves.albums)) { album in
                    AlbumTile(album: album, art: art, covers: covers)
                        .onTapGesture { onOpen(album) }
                }
            }
            .padding(.horizontal, AlbumWall.edge)
        }
    }
}
