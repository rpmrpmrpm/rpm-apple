import SwiftUI
import RPMSharedUI
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
struct PlaylistWall<Footer: View>: View {
    let rows: [PlaylistRow]
    let covers: any CoverStore

    /// How wide a tile should be. The actual width is this value adjusted to a whole number of
    /// columns. See ``WallLayout/wall(available:targetStride:edge:gutter:maxColumns:minColumns:)``,
    /// which is the same calculation that the records wall uses, not a copy of it.
    let targetStride: Double

    let onPress: (PlaylistRow) -> Void

    /// A pinch, given as a factor on the target stride, and nil when the fingers lift. The
    /// records wall reports its pinch the same way. The wall does not own the size it is drawn at.
    let onPinch: (Double?) -> Void

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
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AlbumWall.gutter),
                                   count: columns),
                    spacing: 0
                ) {
                    ForEach(rows) { row in
                        PlaylistTile(row: row, art: art, covers: covers)
                            .onTapGesture { onPress(row) }
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

/// One playlist, folder or generated list on the wall: the square cover and the name under it.
///
/// **This card has the same measurements as the records wall's card.** A playlist and a record
/// are both pictures in a grid of pictures, so they should have the same size. The text is the
/// only difference. A record has a title above an artist, but a playlist has only a name, so the
/// name uses the space of both lines and wraps as much as it needs. See
/// ``AlbumCaption/nameRoom``.
struct PlaylistTile: View {
    let row: PlaylistRow
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
                           edge: art, corner: 10, mark: glyphSize, covers: covers,
                           framed: FramedList.of(row.set))

            Spacer().frame(height: AlbumCaption.artGap)

            Text(row.title)
                .font(.system(size: caption.album, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                // At the TOP of its space, so a one-line name sits directly under the picture
                // and not in the middle of the space that two lines would use.
                .frame(width: art, height: caption.nameRoom, alignment: .top)

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
    /// The name shown on screen. The two lists that no user created are named here, because
    /// they have no name stored anywhere else: the queue is what is playing, and the favourite
    /// songs are a query over the rows.
    var title: String {
        switch kind {
        case .queue: Loc.get("AlbumMenu_PlaylistNowPlaying")
        case .favorites: Loc.get("Playlists_FavoriteTracks")
        case .folder, .playlist: name
        }
    }

    /// The mark shown for a row that has no picture of its own.
    var mark: String {
        switch kind {
        case .queue: Glyph.queue
        case .favorites: Glyph.heart
        case .folder: Glyph.folder
        case .playlist: Glyph.record
        }
    }
}
