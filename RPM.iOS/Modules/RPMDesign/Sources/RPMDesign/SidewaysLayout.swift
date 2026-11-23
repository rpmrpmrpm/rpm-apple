import Foundation
import CoreGraphics

/// Where everything on the modern player on its side goes, worked out from the size of the whole
/// screen, so it holds on any phone on its side.
///
/// **The places are shares of the screen's full width and height**, measured from the drawing the
/// layout follows: an iPhone on its side, 844 by 390 points. The pieces keep the sizes they have in
/// the upright player, scaled by the screen's height against the drawing's (``scale``), because the
/// drawing shows them at those sizes.
///
/// **Nothing is put under the sensor housing or the home indicator.** An element whose place reaches
/// past the safe area is moved in by the difference only. The column's two edges are each held inside
/// on their own, and the spectrum is cut at the edge instead of moving the cover.
///
/// **The cover sits further in than in the Android app's drawing** (``coverX``): on an iPhone on its
/// side the sensor housing takes the left edge, so the cover is moved right, and the spectrum with it,
/// so the bars on its left are not cut by the housing.
///
/// The player's pieces are given whole frames: the words (the title, the artist and the heart), the
/// needle (the seek bar and the clocks), the transport and the capsule. The title's line, the heart,
/// the seek line and the clocks' line inside them follow from the pieces' own layout in the upright
/// player, which this repeats. A ``Marquee`` draws its line at the top of its height.
public struct SidewaysLayout: Sendable, Equatable {
    /// The screen's full size, in points.
    public let width: CGFloat
    public let height: CGFloat

    /// The part of the screen inside the safe area, in points from the screen's top leading corner.
    public let safe: CGRect

    /// The pieces' sizes against their upright ones.
    public let scale: CGFloat

    /// The cover, square: two thirds of the height, left of the middle. On a screen much less wide
    /// than the drawing it keeps to its share of the width.
    public let cover: CGRect

    /// The span the spectrum bars run across, on the cover's rows. The bars run out of both sides of
    /// the cover to the span's ends.
    public let spectrum: CGRect

    /// The spectrum's span made even about the cover's middle. The spectrum is drawn centred on the
    /// cover in this, and cut to ``spectrum``.
    public let spectrumReach: CGRect

    /// Where the lyrics go when they take the cover's place: the spectrum's span, from top to bottom.
    public let lyrics: CGRect

    /// The column the words, the needle, the transport and the capsule share: its two edges, from the
    /// title's top to the capsule's foot.
    public let column: CGRect

    /// The title's line, beside the heart. The tops of its capitals are on the drawing's line.
    public let title: CGRect

    /// The artist's line, under the title's.
    public let artist: CGRect

    /// The heart's key, at the top of the words, reaching past the column so that its glyph ends on
    /// the column's edge.
    public let heart: CGRect

    /// The words: the title, the artist and the heart.
    public let words: CGRect

    /// The seek bar's strip, which takes the finger, centred on the bar's line.
    public let seek: CGRect

    /// The clocks' line, under the bar.
    public let times: CGRect

    /// The needle: the seek bar with the room above it, and the clocks.
    public let needle: CGRect

    /// The transport's row of keys: previous, play in the middle, next.
    public let transport: CGRect

    /// The glass capsule with the lyrics, queue and menu keys.
    public let capsule: CGRect

    /// The cast key, in the top trailing corner.
    public let cast: CGRect

    /// The visualiser key, to the leading side of the cast key, on its line.
    public let visual: CGRect

    /// The layout for a screen `width` by `height` points whose safe area is `safe`.
    public init(width: CGFloat, height: CGFloat, safe: CGRect) {
        self.width = width
        self.height = height
        self.safe = safe
        let s = height / Self.drawnHeight
        scale = s

        let tall = height * Self.coverOfHeight
        let side = width / height < Self.narrow ? min(tall, width * Self.coverOfWidth) : tall
        cover = Self.around(width * Self.coverX, height * Self.coverY, side, side).inside(safe)

        let runLeft = max(cover.midX - width * Self.runReach, safe.minX)
        let runRight = min(cover.midX + width * Self.runReach, safe.maxX)
        spectrum = CGRect(x: runLeft, y: cover.minY, width: runRight - runLeft, height: cover.height)
        let reach = max(cover.midX - runLeft, runRight - cover.midX)
        spectrumReach = CGRect(x: cover.midX - reach, y: cover.minY, width: reach * 2, height: cover.height)
        lyrics = CGRect(x: spectrum.minX, y: safe.minY, width: spectrum.width, height: safe.height)

        let left = max(width * Self.columnLeft, safe.minX)
        let right = min(width * Self.columnRight, safe.maxX)

        let type = Self.titleType * s
        let baseline = height * Self.titleInkTop + type * Self.cabinInk
        title = CGRect(x: left, y: baseline - type * Self.cabinAscent,
                       width: right - left - (Self.wordsGap + Self.heartKey - Self.heartReach) * s,
                       height: Self.titleLine * s)
        artist = CGRect(x: left, y: title.maxY + Self.linesGap * s, width: title.width,
                        height: Self.artistLine * s)
        heart = CGRect(x: right - (Self.heartKey - Self.heartReach) * s, y: title.minY,
                       width: Self.heartKey * s, height: Self.heartKey * s)
        words = CGRect(x: left, y: title.minY, width: right - left, height: artist.maxY - title.minY)

        seek = Self.around((left + right) / 2, height * Self.seekLine, right - left, Self.seekStrip * s)
        times = CGRect(x: left, y: seek.maxY + Self.clocksGap * s, width: right - left,
                       height: Self.clocksType * Self.cabinLine * s)
        needle = CGRect(x: left, y: seek.minY - Self.seekAbove * s, width: right - left,
                        height: times.maxY - seek.minY + Self.seekAbove * s)

        transport = Self.around(width * Self.transportX, height * Self.transportLine,
                                (2 * Self.skipKey + 2 * Self.transportGap + Self.playKey) * s,
                                Self.playKey * s).inside(safe)
        capsule = Self.around(width * Self.capsuleX, height * Self.capsuleLine,
                              3 * Self.smallKey * s, Self.smallKey * s).inside(safe)
        column = CGRect(x: left, y: title.minY, width: right - left, height: capsule.maxY - title.minY)

        cast = Self.around(width * Self.castX, height * Self.castY,
                           Self.glassKey * s, Self.glassKey * s).inside(safe)
        visual = CGRect(x: cast.minX - (Self.keysGap + Self.glassKey) * s, y: cast.minY,
                        width: cast.width, height: cast.height).inside(safe)
    }

    private static func around(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    /// The height of the drawing, at which the pieces have their upright sizes.
    public static let drawnHeight: CGFloat = 390

    // The places, as shares of the full width (x, left, right) or height (y, line, top).
    static let coverX: CGFloat = 0.2954
    static let coverY: CGFloat = 0.5035
    static let coverOfHeight: CGFloat = 0.667
    /// Below this width to height, the cover keeps to ``coverOfWidth`` of the width.
    static let narrow: CGFloat = 1.8
    static let coverOfWidth: CGFloat = 0.42
    /// How far the spectrum runs out from the cover's middle on each side.
    static let runReach: CGFloat = 0.22925
    static let columnLeft: CGFloat = 0.557
    static let columnRight: CGFloat = 0.961
    /// The top of the title's capitals.
    static let titleInkTop: CGFloat = 0.388
    /// The middle of the seek bar.
    static let seekLine: CGFloat = 0.5556
    /// The play key's middle.
    static let transportX: CGFloat = 0.7595
    static let transportLine: CGFloat = 0.743
    static let capsuleX: CGFloat = 0.7575
    static let capsuleLine: CGFloat = 0.904
    static let castX: CGFloat = 0.959
    static let castY: CGFloat = 0.0846

    // The pieces' upright sizes, in points: the player's own.
    static let titleType: CGFloat = 22
    static let titleLine: CGFloat = 28
    static let linesGap: CGFloat = 2
    static let artistType: CGFloat = 15
    static let artistLine: CGFloat = 20
    static let wordsGap: CGFloat = 8
    static let heartKey: CGFloat = 40
    static let heartGlyph: CGFloat = 15
    /// How far the heart's key reaches past the words' edge: about the room beside its glyph.
    static let heartReach: CGFloat = 12
    static let seekAbove: CGFloat = 6
    static let seekStrip: CGFloat = 20
    static let clocksGap: CGFloat = 4
    static let clocksType: CGFloat = 11
    static let skipKey: CGFloat = 56
    static let playKey: CGFloat = 68
    static let transportGap: CGFloat = 24
    static let smallKey: CGFloat = 40
    static let glassKey: CGFloat = 40
    static let keysGap: CGFloat = 10

    // Cabin, as shares of its size: the top of its capitals and tall letters over the baseline, and
    // its line's ascent and height.
    static let cabinInk: CGFloat = 0.75
    static let cabinAscent: CGFloat = 0.965
    static let cabinLine: CGFloat = 1.215
}

private extension CGRect {
    /// This rectangle moved in by the least that puts it inside `safe`: an inset that reaches past
    /// an edge moves it by the difference and no more.
    func inside(_ safe: CGRect) -> CGRect {
        var dx: CGFloat = 0
        if minX < safe.minX { dx = safe.minX - minX } else if maxX > safe.maxX { dx = safe.maxX - maxX }
        var dy: CGFloat = 0
        if minY < safe.minY { dy = safe.minY - minY } else if maxY > safe.maxY { dy = safe.maxY - maxY }
        return offsetBy(dx: dx, dy: dy)
    }
}
