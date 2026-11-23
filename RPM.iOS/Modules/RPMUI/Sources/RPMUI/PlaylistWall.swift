import SwiftUI
import RPMSharedUI
import RPMStages
import RPMKit
import RPMLibrary
import RPMDesign

/// How the playlists are shown: as covers of what is in this folder, or as rows.
///
/// Ported from `PlaylistViewMode` in the desktop app, which is the segment above its tree.
/// The choice is saved in the user defaults, so the tab opens in the layout the user last
/// chose.
public enum PlaylistLayout: String, CaseIterable, Sendable {
    case grid
    case list

    var label: String {
        switch self {
        case .grid: Loc.get("Playlists_ViewIcons")
        case .list: Loc.get("Playlists_ViewList")
        }
    }

    var mark: String {
        switch self {
        case .grid: Glyph.grid
        case .list: Glyph.rows
        }
    }
}

/// The key in the playlists header that switches between the two layouts.
///
/// It is a menu and not a toggle key. A toggle must show either the current layout or the one
/// that pressing it gives. Both are reasonable, so the user cannot know which one it shows
/// until they press it.
struct PlaylistLayoutKey: View {
    @Binding var layout: PlaylistLayout

    var body: some View {
        Menu {
            Picker(Loc.get("Rpm_Library_View"), selection: $layout) {
                ForEach(PlaylistLayout.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
        } label: {
            Text(layout.mark)
                .font(RPMFont.icon(15))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Loc.get("Rpm_Library_View"))
    }
}

/// The covers of one folder's contents, drawn the way the records wall draws a library.
///
/// Ported from `PlaylistView.Icons` in the desktop app. This view does not change the tree.
/// Which folder is open is state of the page, and the rows layout uses the same state. When the
/// user switches between the two layouts, the other one shows the same folder.
///
/// **It draws the rows it is given and decides nothing.** ``PlaylistBrowse`` decides which rows
/// belong to the open folder, and the rows layout is built from the same answer, so the two
/// layouts always agree about what is in a folder.
struct PlaylistWall<Header: View, Footer: View>: View {
    let rows: [PlaylistRow]
    let covers: any CoverStore

    /// The name of the person whose collection is shown, for the line under a playlist's name.
    /// Nil when it is not known. See ``PlaylistRow/byline(owner:)``.
    let owner: String?

    /// How wide a tile should be. The actual width is this value adjusted to a whole number of
    /// columns. See ``WallLayout/wall(available:targetStride:edge:gutter:maxColumns:minColumns:)``,
    /// which is the same calculation that the records wall uses, not a copy of it.
    let targetStride: Double

    let onPress: (PlaylistRow) -> Void

    /// A pinch, given as a factor on the target stride, and nil when the fingers lift. The
    /// records wall reports its pinch the same way. The wall does not own the size it is drawn at.
    let onPinch: (Double?) -> Void

    /// The rows over the covers: the page's shelf of the songs played lately and the pinned lists.
    /// Drawn as rows in this layout too, across the whole width, so they read as a shelf of their
    /// own and not as more covers.
    @ViewBuilder let header: () -> Header

    /// The text under the last tile. It belongs to the page and not to the wall: an empty folder
    /// and an account with no playlists at all are two different cases, and only the page knows
    /// both.
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        GeometryReader { geometry in
            let (columns, art) = WallLayout.wall(
                available: geometry.size.width,
                targetStride: targetStride,
                edge: AlbumWall.edge,
                gutter: AlbumWall.gutter,
                maxColumns: AlbumWall.maxColumns,
                minColumns: AlbumWall.minColumns)

            DissolvingScroll {
                header()

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AlbumWall.gutter),
                                   count: columns),
                    spacing: 0
                ) {
                    ForEach(rows) { row in
                        PlaylistTile(row: row, line: row.byline(owner: owner), art: art,
                                     covers: covers)
                            .onTapGesture { onPress(row) }
                            // Pin it, or put it on Quick selection. See ``Holds``.
                            .listHold(row.set)
                    }
                }
                .padding(.horizontal, AlbumWall.edge)
                .padding(.top, 4)

                footer()

                Color.clear.frame(height: RPMLayout.foot)
            }
            .scrollIndicators(.hidden)
            // `simultaneousGesture`, not `gesture`: a plain gesture loses to the scroll view's
            // own pan and never fires. The records wall handles the pinch the same way.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { onPinch($0.magnification) }
                    .onEnded { _ in onPinch(nil) })
        }
    }
}

/// One playlist, folder or generated list on the wall: the square cover, the name under it, and
/// one quiet line under the name.
///
/// **This card has the same measurements as the records wall's card.** A playlist and a record
/// are both pictures in a grid of pictures, so they should have the same size. The name takes
/// the record's title line and ``line`` takes its artist line, in the same type. See
/// ``PlaylistRow/byline(owner:)`` for what that line says.
struct PlaylistTile: View {
    let row: PlaylistRow

    /// The line under the name, where a record shows its artist.
    let line: String

    let art: Double
    let covers: any CoverStore

    private var caption: AlbumCaption { .of(art: art) }

    var body: some View {
        VStack(spacing: 0) {
            // The background of a generated list's window does not animate here. It is a
            // shader that runs as long as the square is on screen. A wall shows a screenful of
            // squares at once, but a row of the list shows only one. The desktop app makes the
            // same distinction between its cards and its tree.
            PlaylistSleeve(list: row.picture, track: row.artSource, glyph: row.mark,
                           edge: art, mark: glyphSize, covers: covers,
                           framed: FramedList.of(row.set), markPicture: row.markPicture,
                           folder: row.face, folderFrame: row.folderFrame)

            Spacer().frame(height: AlbumCaption.artGap)

            Text(row.title)
                .font(RPMFont.text(caption.album, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: art, height: caption.albumLine)

            Spacer().frame(height: AlbumCaption.lineGap)

            // The record's artist line: the same size and the same quiet colour.
            Text(line)
                .font(RPMFont.display(caption.artist))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: art, height: caption.artistLine)

            Spacer().frame(height: AlbumCaption.below)
        }
        .frame(width: art, height: caption.card, alignment: .top)
        // The whole tile responds to a tap, not only the square. A tap on the name of a list
        // is a tap on the list.
        .contentShape(Rectangle())
    }

    /// The size of the mark on an empty square. It depends on the art edge and is not a fixed
    /// value: the wall is pinched between one and four columns, and a glyph that suits two
    /// columns is far too big at one column and far too small at four. The records wall uses
    /// the same rule.
    private var glyphSize: Double { min(max(art * 0.2, 16), 52) }
}

// ── what a row is called, and its mark ──

extension PlaylistRow {
    /// The name shown on screen. The favourite songs are named here, in this app's language,
    /// because they are a query over the catalogue and the computer's name for its copy may be
    /// in another language.
    var title: String {
        switch kind {
        case .favorites: Loc.get("Playlists_FavoriteTracks")
        case .folder, .playlist: name
        }
    }

    /// The line under the name, where a record shows its artist: what kind of row this is.
    ///
    /// - A folder says that it is a folder.
    /// - A list somebody made names the person whose collection is shown. Only the owner of a
    ///   collection can make lists in it.
    /// - A mood list names the genre it is cut to. A list cut across all genres (a whole mood, or
    ///   a decade) says that it is a mood list.
    /// - The listening lists and the marked songs are neither. They say how much they hold.
    ///
    /// The genre is the genres wall's name for it (``Genres/match(_:)``), so a list and the wall
    /// call the same music by the same name. Genre names are not translated anywhere.
    ///
    /// - Parameter owner: the name of the person whose collection this is, or nil when it is not
    ///   known. A list somebody made then says only that it is a playlist.
    func byline(owner: String?) -> String {
        switch kind {
        case .folder:
            return Loc.get("Playlists_RowFolder")

        case .favorites:
            return PlaylistWords.holding(tracks.count, duration, missing: missing)

        case .playlist(let set):
            guard set.origin == .generated else {
                guard let owner, !owner.isEmpty else { return Loc.get("Home_QuickPlaylist") }
                return Loc.get("Playlists_RowBy", owner)
            }

            if GeneratedLists.ownerOnly.contains(set.cut?.kind ?? "") {
                return PlaylistWords.holding(tracks.count, duration, missing: missing)
            }

            if let genre = set.cut?.genre?.trimmingCharacters(in: .whitespacesAndNewlines),
               !genre.isEmpty {
                return Genres.match(genre) ?? genre
            }
            return Loc.get("Playlists_RowMood")
        }
    }

    /// The mark shown for a row that has no picture of its own. A folder of the app's lists
    /// shows the desktop's mark for it. See ``FolderFace``.
    var mark: String {
        switch kind {
        case .favorites: Glyph.heart
        case .playlist: Glyph.record
        case .folder(_, let face):
            switch face {
            case .decades: Glyph.decades
            case .mood(let kind): Glyph.mood(kind) ?? Glyph.folder
            case .moods, .plain: Glyph.folder
            }
        }
    }

    /// The picture shown in place of ``mark``, or nil. Only the moods folder has one: the
    /// desktop's `moods-folder.png`. It is a picture and not a glyph, because it is shaded and a
    /// font draws one colour.
    @MainActor var markPicture: UIImage? {
        face == .moods ? Self.moodsMark : nil
    }

    /// The frame of one of the app's own folders, or nil. See ``FramedList/folder(_:name:)``.
    var folderFrame: FramedList? {
        face.flatMap { FramedList.folder($0, name: title) }
    }

    /// Read once. Every moods folder row shows the same picture.
    @MainActor private static let moodsMark: UIImage? =
        Bundle.module.url(forResource: "moods-folder", withExtension: "png")
            .flatMap { UIImage(contentsOfFile: $0.path) }
}
