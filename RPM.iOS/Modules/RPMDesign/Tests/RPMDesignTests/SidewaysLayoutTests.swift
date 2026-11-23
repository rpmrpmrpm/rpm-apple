import Testing
import Foundation
import CoreGraphics
@testable import RPMDesign

/// The modern player on its side against the drawing it follows: every place in the table of
/// measurements, as shares of the full screen, on an iPhone on its side (2532 by 1170 pixels at 3
/// to the point) and on a phone of 2340 by 1080 pixels at 2.8125 to the point.
struct SidewaysLayoutTests {
    private static let iphone = SidewaysLayout(width: 844, height: 390,
                                               safe: CGRect(x: 0, y: 0, width: 844, height: 390))
    private static let phone = SidewaysLayout(width: 832, height: 384,
                                              safe: CGRect(x: 0, y: 0, width: 832, height: 384))

    @Test func theIphoneMatchesTheDrawing() { matchesTheDrawing(Self.iphone) }

    @Test func theWiderPhoneMatchesTheDrawing() { matchesTheDrawing(Self.phone) }

    private func near(_ expected: CGFloat, _ actual: CGFloat, _ slack: CGFloat = 0.002) -> Bool {
        abs(expected - actual) <= slack
    }

    private func matchesTheDrawing(_ laid: SidewaysLayout) {
        let w = laid.width
        let h = laid.height
        let s = laid.scale

        // The cover: two thirds of the height, square.
        #expect(near(0.079, laid.cover.minX / w))
        #expect(near(0.170, laid.cover.minY / h))
        #expect(near(0.837, laid.cover.maxY / h))
        #expect(abs(laid.cover.width - laid.cover.height) < 0.001)
        #expect(near(0.233, laid.cover.midX / w))

        // The spectrum runs from near the left edge, past the cover, to short of the middle, on the
        // cover's rows, and with nothing in the way it is even about the cover.
        #expect(near(0.004, laid.spectrum.minX / w))
        #expect(near(0.4625, laid.spectrum.maxX / w))
        #expect(laid.spectrum.minY == laid.cover.minY)
        #expect(laid.spectrum.height == laid.cover.height)
        #expect(abs(laid.spectrumReach.midX - laid.cover.midX) < 0.001)

        // The column's two edges.
        #expect(near(0.557, laid.column.minX / w))
        #expect(near(0.961, laid.column.maxX / w))
        #expect(laid.words.minX == laid.column.minX)
        #expect(laid.needle.minX == laid.column.minX)
        #expect(laid.needle.maxX == laid.column.maxX)

        // The title, drawn at the top of its line, and the artist under it.
        let title = SidewaysLayout.titleType * s
        let titleBaseline = laid.title.minY + title * SidewaysLayout.cabinAscent
        #expect(near(0.388, (titleBaseline - title * SidewaysLayout.cabinInk) / h))
        #expect(near(0.431, titleBaseline / h))
        #expect(near(0.557, laid.title.minX / w))
        let artist = SidewaysLayout.artistType * s
        let artistBaseline = laid.artist.minY + artist * SidewaysLayout.cabinAscent
        #expect(near(0.461, (artistBaseline - artist * SidewaysLayout.cabinInk) / h))
        #expect(near(0.498, (artistBaseline + artist * 0.242) / h))

        // The heart's glyph ends on the column's right edge, level with the title.
        #expect(near(0.961, (laid.heart.midX + SidewaysLayout.heartGlyph / 2 * s) / w, 0.0015))
        #expect(near(0.427, laid.heart.midY / h, 0.003))

        // The seek bar's line, its knob, and the clocks under it.
        #expect(near(0.555, laid.seek.midY / h))
        #expect(near(0.5376, (laid.seek.midY - 7 * s) / h))
        #expect(near(0.5726, (laid.seek.midY + 7 * s) / h, 0.0025))
        #expect(near(0.557, laid.seek.minX / w))
        #expect(near(0.961, laid.seek.maxX / w))
        let clocks = SidewaysLayout.clocksType * s
        #expect(near(0.598, (laid.times.minY + clocks * (SidewaysLayout.cabinAscent - 0.7145)) / h))
        #expect(near(0.618, (laid.times.minY + clocks * SidewaysLayout.cabinAscent) / h, 0.0015))

        // The transport: previous and next glyphs at their edges, play in the middle.
        #expect(near(0.743, laid.transport.midY / h))
        #expect(near(0.6445, (laid.transport.minX + (28 - 11) * s) / w))
        #expect(near(0.874, (laid.transport.maxX - (28 - 11) * s) / w))
        #expect(near(0.759, laid.transport.midX / w))
        #expect(near(0.057, 26 * 0.875 * s / h))

        // The capsule of keys.
        #expect(near(0.757, laid.capsule.midX / w))
        #expect(near(0.903, laid.capsule.midY / h))
        #expect(near(0.145, laid.capsule.width / w, 0.004))
        #expect(near(0.097, laid.capsule.height / h, 0.006))
        #expect(laid.capsule.maxY == laid.column.maxY)

        // The cast key in the corner, and the visualiser key 10 points to its left on its line.
        #expect(near(0.959, laid.cast.midX / w))
        #expect(near(0.084, laid.cast.midY / h))
        #expect(near(0.103, laid.cast.height / h))
        #expect(laid.visual.midY == laid.cast.midY)
        #expect(abs(laid.cast.minX - laid.visual.maxX - 10 * s) < 0.001)
        #expect(laid.visual.size == laid.cast.size)
    }

    /// The sensor housing and the home indicator: what reached into them moves in by the
    /// difference, and nothing else moves.
    @Test func nothingIsOutsideTheSafeArea() {
        let safe = CGRect(x: 47, y: 0, width: 750, height: 369)
        let laid = SidewaysLayout(width: 844, height: 390, safe: safe)
        let frames = [laid.cover, laid.spectrum, laid.lyrics, laid.column, laid.words, laid.needle,
                      laid.transport, laid.capsule, laid.cast, laid.visual]
        for frame in frames {
            #expect(safe.insetBy(dx: -0.001, dy: -0.001).contains(frame))
        }
        // The spectrum is cut at the edge; the cover stays where it was, and the spectrum is still
        // drawn even about it.
        #expect(abs(laid.spectrum.minX - 47) < 0.001)
        #expect(laid.cover == Self.iphone.cover)
        #expect(abs(laid.spectrumReach.midX - laid.cover.midX) < 0.001)
        // The column's right edge, the cast key and the capsule move in by the difference only.
        #expect(abs(laid.column.maxX - 797) < 0.001)
        #expect(laid.column.minX == Self.iphone.column.minX)
        #expect(abs(laid.cast.maxX - 797) < 0.001)
        #expect(abs(laid.capsule.maxY - 369) < 0.001)
        #expect(laid.capsule.midX == Self.iphone.capsule.midX)
        #expect(laid.transport == Self.iphone.transport)
    }

    /// A phone much less wide than the drawing keeps the rules, with the cover held to its share of
    /// the width.
    @Test func aSquarerScreenHoldsTheCoverToItsWidth() {
        let laid = SidewaysLayout(width: 600, height: 400,
                                  safe: CGRect(x: 0, y: 0, width: 600, height: 400))
        #expect(abs(laid.cover.width - 0.42 * 600) < 0.001)
        #expect(abs(laid.cover.midX - 0.233 * 600) < 0.001)
        #expect(laid.cover.maxX < laid.column.minX)
    }
}
