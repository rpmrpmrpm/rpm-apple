import SwiftUI
import RPMKit
import RPMLibrary
import RPMDesign

/// The wall of records.
///
/// It is handed a width and works out its own columns, because the sizing is one
/// rule (`WallLayout.fit`) and a wall that asked its cards how big they were would
/// be a wall whose rows disagree about their height.
///
/// **`LazyVGrid`, chosen after measuring.** A `LazyVGrid` and a UIKit collection view
/// both scrolled a real collection of eleven hundred records smoothly on a real phone,
/// cold. The `LazyVGrid` is much shorter and needs no UIKit bridge, so it is used. If a
/// library turns up that it cannot hold, a collection view is the alternative.
public struct AlbumWall: View {
    private let albums: [CloudAlbum]
    private let covers: any CoverStore
    private let targetStride: Double
    private let onOpen: (CloudAlbum) -> Void

    /// A pinch, as a factor on the target stride: 1 is no change.
    ///
    /// Reported upward rather than handled here, because the wall does not own the
    /// number it is drawn at. `nil` at the end of the gesture is the caller's cue
    /// to keep whatever it last saw.
    private let onPinch: (Double?) -> Void

    /// The gap between cards.
    public static let gutter: Double = 24

    /// The inset at either edge of the wall.
    ///
    /// **The app's margin, not half the gutter.** The first column lines up with the
    /// screen's title only if this is ``RPMLayout/margin``, so there is one number to change.
    ///
    /// It is separate from ``gutter`` because they answer different questions: one is the
    /// space between two covers, the other is the space between a cover and the edge of the
    /// screen. They are not related.
    public static let edge: Double = RPMLayout.margin

    /// One across is a cover the width of the phone. Four across is as small as a name
    /// can be and still be read.
    public static let maxColumns = 4
    public static let minColumns = 1

    public init(
        albums: [CloudAlbum],
        covers: any CoverStore,
        targetStride: Double = 194,
        onOpen: @escaping (CloudAlbum) -> Void = { _ in },
        onPinch: @escaping (Double?) -> Void = { _ in }
    ) {
        self.albums = albums
        self.covers = covers
        self.targetStride = targetStride
        self.onOpen = onOpen
        self.onPinch = onPinch
    }

    public var body: some View {
        GeometryReader { geometry in
            // The margins go INTO the sizing rather than being applied over it: a
            // wall measured against the whole screen and then inset lays out cards
            // wider than the columns holding them. ``WallLayout/wall`` is the one
            // place that arithmetic lives, and the one place it is tested.
            let (columns, art) = WallLayout.wall(
                available: geometry.size.width,
                targetStride: targetStride,
                edge: Self.edge,
                gutter: Self.gutter,
                maxColumns: Self.maxColumns,
                minColumns: Self.minColumns)

            LazyGridWall(albums: albums, covers: covers, columns: columns,
                         art: art, onOpen: onOpen)
                // simultaneousGesture, not gesture: a plain one loses the race to
                // the ScrollView's own pan and never fires.
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { onPinch($0.magnification) }
                        .onEnded { _ in onPinch(nil) })
        }
    }
}

// ── SwiftUI's own ──

private struct LazyGridWall: View {
    let albums: [CloudAlbum]
    let covers: any CoverStore
    let columns: Int
    let art: Double
    let onOpen: (CloudAlbum) -> Void

    var body: some View {
        // The covers dissolve into the top edge rather than being cut off on the line
        // under the heading: see ``DissolvingScroll``.
        DissolvingScroll {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AlbumWall.gutter),
                               count: columns),
                spacing: 0
            ) {
                ForEach(albums) { album in
                    AlbumTile(album: album, art: art, covers: covers)
                        .onTapGesture { onOpen(album) }
                }
            }
            .padding(.horizontal, AlbumWall.edge)
            // Matches the desktop's `Margin="2,4,2,16"` on its repeater, which sets the
            // gap between the counts line and the first sleeve.
            .padding(.top, 4)
            // The room for the chrome is reserved by the page; this is the gap between
            // the last row of names and the top of it. See ``RPMLayout/foot``.
            .padding(.bottom, RPMLayout.foot)
        }
    }
}
