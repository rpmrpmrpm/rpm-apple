import SwiftUI
import RPMKit
import RPMLibrary
import RPMRadio
import RPMArt
import RPMSharedUI

/// The width of a record card's cover on the rows and the wall.
enum Card {
    static let edge: CGFloat = 260
    /// Six cards and five gaps fill the 1760 points between the margins exactly. A seventh card is
    /// then partly visible at the screen's edge.
    static let gap: CGFloat = 40
    /// A wide card, for a genre or a station's room. Four cards and three gaps fit between the
    /// margins.
    static let wide: CGFloat = (1920 - 2 * Size.side - 3 * gap) / 4
}

/// A record on a row or the wall: its cover, which lifts under the focus as tvOS lifts a poster,
/// and its title and artist below it.
///
/// Every card follows Apple's tvOS lockup. The picture and the text lines are direct children of
/// the label. The borderless style then stacks them, and moves the text down as the picture grows.
/// `.hoverEffect(.highlight)` is on the whole clipped square. Without that, the style lifts the
/// first image it finds. For a list in a frame, that is the photo under the frame. It then grows
/// inside its clip, and the frame's edges are cut off. Select opens the page. Press and hold shows
/// Play and Shuffle.
struct AlbumCard: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let album: CloudAlbum
    var edge: CGFloat = Card.edge

    var body: some View {
        Button {
            screens.open(.album(album.key))
        } label: {
            Sleeve(album: album, edge: edge)
                .hoverEffect(.highlight)
            CardLines(title: AlbumNames.title(album), line: AlbumNames.artist(album),
                      explicit: album.tracks.contains(where: \.isExplicit), width: edge)
        }
        .buttonStyle(.borderless)
        .remembered("album:" + album.key)
        .contextMenu {
            Button(Loc.get("AlbumMenu_Play"), systemImage: "play.fill") { model.play(album.tracks, from: 0) }
            Button(Loc.get("AlbumMenu_Shuffle"), systemImage: "shuffle") { model.shuffle(album.tracks) }
        }
    }
}

/// A playlist on the Made for you and Playlists screens: its picture and frame, its name, and its
/// mood sentence or its length.
struct ListCard: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let set: PlaylistSet
    var edge: CGFloat = Card.edge
    /// The caption on the Playlists screen is the folder. On home it is the mood sentence.
    var onShelf = false

    var body: some View {
        Button {
            screens.open(.list(set.id))
        } label: {
            ListPicture(set: set, edge: edge, drifts: true)
                .hoverEffect(.highlight)
            CardLines(title: set.name, line: onShelf ? ListLines.shelf(set) : ListLines.caption(set),
                      explicit: set.tracks.contains(where: \.isExplicit), width: edge)
        }
        .buttonStyle(.borderless)
        .remembered("list:" + set.id)
        .contextMenu {
            Button(Loc.get("Playlists_Play"), systemImage: "play.fill") { model.play(set.tracks, from: 0) }
            Button(Loc.get("AlbumMenu_Shuffle"), systemImage: "shuffle") { model.shuffle(set.tracks) }
        }
    }
}

/// The favourite songs as a card on the Playlists screen. Opens their list page.
struct FavouritesCard: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let tracks: [CloudTrack]

    var body: some View {
        Button {
            screens.open(.favourites)
        } label: {
            FavouritesPicture(edge: Card.edge)
                .hoverEffect(.highlight)
            CardLines(title: Loc.get("Playlists_FavoriteTracks"), line: Counts.songs(tracks.count),
                      explicit: false, width: Card.edge)
        }
        .buttonStyle(.borderless)
        .remembered("favourites")
        .contextMenu {
            Button(Loc.get("Playlists_Play"), systemImage: "play.fill") { model.play(tracks, from: 0) }
            Button(Loc.get("AlbumMenu_Shuffle"), systemImage: "shuffle") { model.shuffle(tracks) }
        }
    }
}

/// The two text lines under a card's picture: the title, with the E mark for an explicit record,
/// and the artist or other detail.
struct CardLines: View {
    let title: String
    let line: String?
    let explicit: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.tv(Size.cardTitle, .semibold))
                    .foregroundStyle(Ink.card)
                    .lineLimit(1)
                if explicit { ExplicitMark(side: 24) }
            }
            Text(line ?? " ")
                .font(.tv(Size.cardLine))
                .foregroundStyle(Ink.dim)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// A station's card: its logo on a still room in the logo's colours, with the station's name and
/// its place.
struct StationCard: View {
    @Environment(TVModel.self) private var model
    let station: RadioStation
    var width: CGFloat = 300
    var wide = false
    var onTune: () -> Void

    @State private var wearing = Wearing()

    var body: some View {
        let logo = (wide ? width * 9 / 16 : width) * 0.5
        Button(action: onTune) {
            ZStack {
                StationRoom(colours: wearing.of(station, edge: logo), breathes: false, seed: station.uuid)
                StationLogo(station: station, edge: logo, onWearing: { wearing.said($0, by: station) })
            }
            .frame(width: width, height: wide ? width * 9 / 16 : width)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .hoverEffect(.highlight)
            CardLines(title: station.display, line: StationLines.detail(station),
                      explicit: false, width: width)
        }
        .buttonStyle(.borderless)
        .remembered("station:" + station.uuid)
        .contextMenu { StationMenu(station: station) }
    }
}

/// What a station's press-and-hold offers: Play, and Add to or Remove from favourites.
struct StationMenu: View {
    @Environment(TVModel.self) private var model
    let station: RadioStation

    var body: some View {
        Button(Loc.get("Radio_PlayStation"), systemImage: "play.fill") { model.tune(station) }
        // Not on a shared collection, whose saved stations are its owner's.
        if model.savedStations.mayChange {
            if model.radio.saved.contains(station.uuid) {
                Button(Loc.get("Tv_Radio_RemoveFavorite"), systemImage: "heart.slash") { model.radio.saved.remove(station.uuid) }
            } else {
                Button(Loc.get("Tv_Radio_AddFavorite"), systemImage: "heart") { model.radio.saved.add(station) }
            }
        }
    }
}

/// The colours of a station's logo, which light the room behind it. These are the colours the logo
/// reported for this station. If there are none yet, they are the colours it last had at that size
/// (`StationDress.last`). So the room has the right colours from its first frame. It never shows
/// the colours of the previous station while the logo is still loading.
struct Wearing {
    private var station: String?
    private var colours: SleeveColours?

    mutating func said(_ colours: SleeveColours, by station: RadioStation) {
        self.station = station.uuid
        self.colours = colours
    }

    /// `edge` is the logo's size. The stored colours are kept under that size.
    func of(_ station: RadioStation, edge: CGFloat) -> SleeveColours? {
        station.uuid == self.station ? colours : StationDress.last(station.uuid, edge: edge)?.worn.colours
    }
}

/// A room in the station's colours, behind its logo.
struct StationRoom: View {
    let colours: SleeveColours?
    let breathes: Bool
    /// Identifies the room. A row of rooms then does not move in step. See `RoomView.seed`.
    let seed: String

    var body: some View {
        if RoomView.works {
            RoomView(colours: RoomColours.of(colours), sound: .still, foot: 1, running: breathes,
                     breathes: true, zero: .whenShown, seed: seed)
        } else {
            Color.white.opacity(0x1A / 255)
        }
    }
}

/// A horizontal row of cards. It reaches the screen's edges, so a lifted card at either end is not
/// cut off. A scrolled row stops with a card on the left margin. So the first visible card in each
/// row lines up with the headings.
///
/// `space` names the row for the screen's focus memory (``keepsFocus(_:first:)``). One record can
/// appear in two rows, so a card is named within its row. There is no default, so every row must
/// give a name.
struct CardRow<Item: Identifiable, Cell: View>: View {
    let space: String
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Card.gap) {
                ForEach(items) { cell($0) }
            }
            .scrollTargetLayout()
            .padding(.vertical, 24)
            .focusSpace(space)
        }
        // Use margins rather than padding. The cards then line up with the margin, not the screen
        // edge.
        .contentMargins(.horizontal, Size.side, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .focusSection()
    }
}

/// The names shown for a record.
enum AlbumNames {
    static func title(_ album: CloudAlbum) -> String {
        album.album.isEmpty ? (album.tracks.first?.title ?? "") : album.album
    }

    static func artist(_ album: CloudAlbum) -> String {
        album.artist
    }
}

/// Counts with a singular form for 1. The strings match the Android TV app.
enum Counts {
    static func albums(_ count: Int) -> String {
        count == 1 ? Loc.get("Stats_AlbumsOne") : Loc.get("Stats_Albums", String(count))
    }

    static func playlists(_ count: Int) -> String {
        count == 1 ? Loc.get("Stats_PlaylistsOne") : Loc.get("Stats_Playlists", String(count))
    }

    static func songs(_ count: Int) -> String {
        count == 1 ? Loc.get("Stats_SongsOne") : Loc.get("Stats_Songs", String(count))
    }
}

/// The line of text under a list's name. The wording matches the Android TV app.
enum ListLines {
    /// On home (the card, quick selection and the banner), a mood list shows a sentence about the
    /// kinds of music it drew from. Other lists show their count, because their name already says
    /// what they are.
    static func caption(_ set: PlaylistSet) -> String {
        if let cut = set.cut, let sentence = MoodBlurb.sentence(kind: cut.kind, genres: set.tracks.map { $0.tags?.genre }) {
            return sentence
        }
        return count(set)
    }

    /// On the Playlists screen: the folder the list is filed in, or else the number of songs.
    static func shelf(_ set: PlaylistSet) -> String {
        set.folder.isEmpty ? count(set) : set.folder.joined(separator: " / ")
    }

    private static func count(_ set: PlaylistSet) -> String {
        set.tracks.count == 1 ? Loc.get("Rpm_Album_TracksOne") : Loc.get("Rpm_Album_Tracks", String(set.tracks.count))
    }
}

/// A station's second line: its country and quality.
enum StationLines {
    static func detail(_ station: RadioStation) -> String? {
        let country = station.countryCode.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? station.country
        let parts = [country, station.quality.isEmpty ? nil : station.quality].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
