import Foundation

/// How a wall of covers is divided into columns.
///
/// `AnchorLost` is deliberately not here. It checks three invariants to catch a fault in WinUI's
/// `ItemsRepeater`, which loses its place in a virtualising stack. That fault is in that layout and
/// its extent estimate. A `UICollectionView` places items from a layout it computes. It does not
/// place them from a running average of the cards it has built. So there is no estimate to lose, and
/// nothing for the check to catch. Copying the check would copy a workaround for a bug this platform
/// does not have.
public enum WallLayout {
    /// How many cards best fit across a wall `available` points wide, when the target card stride is
    /// `targetStride`.
    ///
    /// Rounds to the NEAREST whole column, not down. The realised card then lands as close to the target
    /// as a whole number of columns allows. For example, 5.5 target columns gives 6 slightly smaller
    /// cards, not 5 wider ones. There is always at least one column. A wall narrower than one card still
    /// shows one, rather than nothing. An unmeasured width gives one, so the first row is never empty.
    public static func columns(for available: Double, targetStride: Double, min: Int = 1) -> Int {
        guard targetStride > 0, available.isFinite, available > 0 else { return min }
        return Swift.max(min, Int((available / targetStride).rounded(.toNearestOrAwayFromZero)))
    }

    /// The realised card stride once the row is split into whole cards. The width is shared out
    /// evenly and **rounded down**, so `columns × stride ≤ available`. The last card is never pushed
    /// off the edge.
    ///
    /// The result is capped. A nearly empty wall, with one card in a wide space, would otherwise enlarge
    /// that card to the full width. An unmeasured width gives the cap, which is the widest a card is
    /// ever allowed to be.
    public static func stride(for available: Double, columns: Int, maxStride: Double) -> Double {
        let columns = Swift.max(1, columns)
        guard available.isFinite, available > 0 else { return maxStride }
        return Swift.min(Swift.max((available / Double(columns)).rounded(.down), 1), maxStride)
    }

    /// Both halves of the sizing in one answer: how many columns a target stride asks for, and the
    /// stride they are laid out at once the row is filled edge to edge.
    ///
    /// The column count is clamped. A pinch needs this, but a slider does not. A pinch can ask for covers
    /// the size of postage stamps. A wall nine albums across on a phone is a texture, not a library.
    public static func fit(
        available: Double, targetStride: Double, maxColumns: Int, minColumns: Int = 1
    ) -> (columns: Int, stride: Double) {
        let low = Swift.max(1, minColumns)
        let high = Swift.max(low, maxColumns)

        let wanted = columns(for: available, targetStride: targetStride, min: low)
        let count = Swift.min(Swift.max(wanted, low), high)

        // The cap is the wall itself. With one column, the card is the full width. That is the result of
        // pinching out that far.
        return (count, stride(for: available, columns: count, maxStride: Swift.max(1, available)))
    }
    /// The whole of a wall's sizing in one answer: how many covers go across, and how wide each one is
    /// drawn.
    ///
    /// **The arithmetic is here, not in the view.** It is the one part of a wall that can be silently
    /// wrong. `fit` above answers in *strides*. A stride is a cover plus the gap that follows it. A caller
    /// that passed the width of the screen to `fit`, and then inset the grid by anything other than half a
    /// gutter, would lay out cards wider than the columns that hold them. Nothing would report it. On a
    /// phone, the cover would simply be clipped at one zoom level.
    ///
    /// - Parameters:
    ///   - available: the width the wall has, edge to edge of the screen.
    ///   - edge: the margin at either side, outside the first and last cover.
    ///   - gutter: the gap between two covers.
    public static func wall(
        available: Double, targetStride: Double, edge: Double, gutter: Double,
        maxColumns: Int, minColumns: Int = 1
    ) -> (columns: Int, art: Double) {
        // A row of n covers is n strides, with the last gap hanging off the end. So the room a stride is
        // measured against is the wall inside its margins, with that one gap given back.
        let room = Swift.max(1, available - 2 * edge + gutter)

        let (columns, stride) = fit(available: room, targetStride: targetStride,
                                    maxColumns: maxColumns, minColumns: minColumns)

        return (columns, Swift.max(1, stride - gutter))
    }
}

/// How big the writing under a cover is, given how big the cover is.
///
/// On a normal phone the wall is pinched between one column and four. The art edge is about 70 points
/// at one end and about 360 at the other. Type that stays the same size across that range is wrong at
/// both ends. At four across, a 15-point title competes with the sleeve it belongs to. At one across,
/// the same title is a footnote under a picture five inches wide.
///
/// The sizes are computed here, apart from the view. The wall must never be asked for the same number
/// twice with two different answers. **Every card in a row shares an art edge, so every card in a row
/// shares these sizes.** This matters. Two cards that size their captions differently are two rows of
/// different heights. Rows of different heights make the wall shift a line under the finger that is
/// reading it.
public struct AlbumCaption: Hashable, Sendable {
    /// The art edge these sizes are drawn against: two columns on a normal phone. This is the size the
    /// wall opens at. At exactly this edge, each figure below has its base value.
    public static let anchor: Double = 170

    private static let anchorAlbum: Double = 15
    private static let anchorArtist: Double = 14
    private static let anchorBadge: Double = 13
    private static let anchorAlbumLine: Double = 20
    private static let anchorArtistLine: Double = 19

    /// The smallest size. It fits four covers across. Below eleven points, a record's name over a
    /// photograph is too small to read at arm's length.
    static let smallest: Double = 11

    /// The largest size. This is a title, not a heading. The sleeve is the thing being looked at, even
    /// when it fills the screen. Above twenty points, the writing under the sleeve competes with it.
    static let largest: Double = 20

    /// The gaps a card is built from, above and below the writing.
    ///
    /// They are here, not in the view, for the same reason the type sizes are. The wall's row height is
    /// the sum of these gaps and the two line heights. A layout must know that height before it builds a
    /// card. Two places holding the same number can disagree, and when they do, the row has the wrong
    /// height.
    public static let artGap: Double = 10
    public static let lineGap: Double = 2
    public static let below: Double = 10

    /// The art edge this caption was drawn against. It is kept so that a card's total height can be asked
    /// of the caption, rather than rebuilt by whoever needs it. This is the EFFECTIVE edge: a cover with no
    /// size gets the edge the wall opens at.
    public let art: Double

    public let album: Double
    public let artist: Double

    /// The size of the E badge, which sits beside the name and grows with it. If the badge stayed one size,
    /// it would look like a mark on the title at four columns, and like a speck at one column.
    public let badge: Double

    /// The height of the name's line with nothing on it, and `artistLine` the same for the line under it.
    /// Both keep their height when empty, so a record with no artist is not a shorter card.
    public let albumLine: Double
    public let artistLine: Double

    /// How tall the whole card is: the sleeve, the two lines under it, and the gaps between them.
    ///
    /// This is the one figure a layout needs, and it cannot measure its way to it.
    public var card: Double { art + Self.artGap + albumLine + Self.lineGap + artistLine + Self.below }

    /// The room a caption gives one piece of writing, rather than two. That is both lines and the gap
    /// between them.
    ///
    /// A playlist tile's name is laid out in this room. A record has a title over an artist. A playlist
    /// has only a name. So the name takes the whole caption and wraps across as much of it as it needs.
    /// The tile is the same height either way. That keeps a row of tiles on one line. It is also the same
    /// height as a record card at the same art edge, because a playlist and a record are both pictures in
    /// a grid. The desktop app uses the same rule, in `PlaylistView.TileCaption`.
    public var nameRoom: Double { albumLine + Self.lineGap + artistLine }

    /// The caption for an art edge of `art` points.
    ///
    /// **Scaled by the square root of the change in edge, not by the change itself.** Type and pictures do
    /// not scale together, because the distance to the reader does not change when the picture does. A cover
    /// with four times the area is viewed from the same place. A title scaled with the width would be twice
    /// the size, for no reason a reader would notice. The square root keeps the writing at a steady share of
    /// the card's AREA, which is how a reader judges it.
    ///
    /// The factor is clamped once, not each figure. That keeps the five numbers in the same relation at both
    /// ends, instead of collapsing into each other at the floor.
    public static func of(art: Double) -> AlbumCaption {
        var factor = art > 0 ? (art / anchor).squareRoot() : 1
        factor = Swift.min(Swift.max(factor, smallest / anchorAlbum), largest / anchorAlbum)

        return AlbumCaption(
            art: art > 0 ? art : anchor,
            album: (anchorAlbum * factor).rounded(toPlaces: 1),
            artist: (anchorArtist * factor).rounded(toPlaces: 1),
            badge: (anchorBadge * factor).rounded(toPlaces: 1),
            // Whole points. A line height is also a row height. Every card on the wall rounds the same way
            // from the same edge. A fraction that rounds differently on two cards is the one difference this
            // type exists to prevent.
            albumLine: (anchorAlbumLine * factor).rounded(),
            artistLine: (anchorArtistLine * factor).rounded())
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (self * scale).rounded() / scale
    }
}
