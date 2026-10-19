import Testing
import Foundation
import CoreGraphics
@testable import RPMArt
import RPMDesign

@Test func aPictureComesBackAtTheSizeItWasAskedFor() {
    let image = try! #require(Thumbnail.of(Pictures.png(field: RGB(120, 40, 160), edge: 900),
                                           edge: 256))

    #expect(Swift.max(image.width, image.height) == 256)
}

/// The point of using ImageIO rather than drawing into a context is that the full-size picture is
/// never decoded. A three-thousand-pixel scan therefore costs about as much as the card, not about
/// 36 megabytes.
@Test func aLargePictureIsNeverDecodedAtItsOwnSize() {
    let huge = Pictures.jpeg(field: RGB(30, 90, 200), edge: 2400)
    let image = try! #require(Thumbnail.of(huge, edge: 170))

    #expect(image.width <= 170 && image.height <= 170)
}

/// A JPEG's own embedded thumbnail is only 160 pixels and is not the real picture. The decoder must
/// not prefer it.
@Test func askingForMoreThanTheFileCarriesIsNotAnErrorAndNotATinyPicture() {
    let small = Pictures.png(field: RGB(200, 60, 40), edge: 120)
    let image = try! #require(Thumbnail.of(small, edge: 1024))

    // Never upscaled by ImageIO, but never smaller than the file either.
    #expect(image.width == 120)
}

@Test func nothingIsNotAPicture() {
    #expect(Thumbnail.of(Data(), edge: 256) == nil)
    #expect(Thumbnail.of(Data("not a picture".utf8), edge: 256) == nil)
    #expect(Thumbnail.of(Pictures.png(field: RGB(1, 2, 3)), edge: 0) == nil)
}

// ── the colour ──

@Test func theSquareIsForFortyEightAcross() {
    let square = try! #require(Thumbnail.square(Pictures.drawn(field: RGB(180, 60, 40))))
    #expect(square.count == 48 * 48 * 4)
}

@Test func aSleeveReadsAsTheColourItIs() {
    let red = Pictures.drawn(field: RGB(60, 40, 40), splash: RGB(225, 30, 25), share: 0.2)
    let accent = try! #require(Thumbnail.accent(of: red))

    #expect(["Vermilion", "Red", "Crimson", "Rust"].contains(accent.name),
            "a red sleeve came out \(accent.name)")
}

/// A black-and-white press shot has no colour to give. The wall keeps the picture's own grey tone
/// instead of snapping it to a palette colour.
@Test func aGreySleeveSnapsToNothing() {
    #expect(Thumbnail.accent(of: Pictures.drawn(field: RGB(4, 4, 4))) == nil)
}

/// The same cover gives the same colour however large the picture is. A record whose colour
/// changed when the wall was zoomed would be worse than one whose shade was slightly wrong.
@Test func theColourDoesNotDependOnHowBigThePictureIs() {
    let bytes = Pictures.png(field: RGB(96, 82, 70), splash: RGB(230, 30, 40),
                             share: 0.25, edge: 1200)

    let names = [256, 512, 1024].map { edge -> String in
        Thumbnail.accent(of: Thumbnail.of(bytes, edge: edge)!)?.name ?? "none"
    }

    #expect(Set(names).count == 1, "read \(names)")
}

/// **The room is lit by the record's own colour, not by one of the app's ten.** A wall of six
/// hundred records looks like one thing because every card snaps to the palette. A room built from
/// those same ten colours would look like ten rooms. So one reading gives up both: the snapped
/// accent for the cards, and the raw pair for the room.
@Test func oneReadingGivesUpTheSnappedAccentAndTheRawPair() throws {
    let brown = RGB(96, 82, 70), vivid = RGB(230, 30, 40)
    let read = Thumbnail.colours(of: Pictures.drawn(field: brown, splash: vivid, share: 0.2))

    let accent = try #require(read.accent)
    let dominant = try #require(read.dominant)
    let highlight = try #require(read.highlight)

    // The field is most of the cover. The splash is the vivid part, a fifth of the cover.
    #expect(near(dominant, brown), "the dominant came out \(dominant)")
    #expect(near(highlight, vivid), "the highlight came out \(highlight)")

    // The accent is neither. It is the app's own colour nearest the cover, which a room must not be
    // built from.
    #expect(accent.base != dominant && accent.base != highlight)
}

/// The reading the walls use comes from the same square. Adding the room's pair must not change
/// the colour each card is drawn in.
@Test func theAccentIsTheSameOneItAlwaysWas() {
    let sleeve = Pictures.drawn(field: RGB(60, 40, 40), splash: RGB(225, 30, 25), share: 0.2)

    #expect(Thumbnail.colours(of: sleeve).accent == Thumbnail.accent(of: sleeve))
}

/// A cover with no colour gives nothing for any of the three readings. That is a valid answer,
/// not a failure. The room then uses the app's own blue.
@Test func aSleeveWithNoColourGivesNoneUp() {
    #expect(Thumbnail.colours(of: Pictures.drawn(field: RGB(4, 4, 4))) == .none)
}

/// Near enough to be the same colour. The buckets are 32 levels per axis, so a reading is the
/// average of all the pixels that fall into one bucket.
private func near(_ a: RGB, _ b: RGB, within: Int = 24) -> Bool {
    abs(Int(a.r) - Int(b.r)) <= within
        && abs(Int(a.g) - Int(b.g)) <= within
        && abs(Int(a.b) - Int(b.b)) <= within
}

// ── keeping it ──

@Test func aPictureKeptForTheDiskIsStillAPicture() {
    let image = Thumbnail.of(Pictures.png(field: RGB(120, 40, 160), edge: 1600),
                             edge: Thumbnail.stored)!
    let kept = try! #require(Thumbnail.encoded(image, .cover))

    let back = try! #require(Thumbnail.of(kept, edge: Thumbnail.stored))
    #expect(back.width == image.width)
}

/// The disk holds a re-encoded copy, not the bytes that arrived. A library of scans can take a
/// gigabyte, and the re-encoded copy takes only a fraction of that.
@Test func keepingItCostsFarLessThanWhatArrived() {
    let arrived = Pictures.png(field: RGB(90, 140, 200), splash: RGB(250, 220, 40),
                               share: 0.3, edge: 3000)
    let kept = try! #require(Thumbnail.encoded(Thumbnail.of(arrived, edge: Thumbnail.stored)!, .cover))

    #expect(kept.count < arrived.count / 4, "kept \(kept.count) of \(arrived.count)")
}

// ── the third colour ──
//
// `RoomPalette` has a rule for a cover's third colour, and its tests cover that rule. This reader
// must also read the third colour. Without it, the room only used the dominant and accent hues.
// When those two are the same hue, the room lit a colour that is not on the cover.

/// A gold cover with red lettering across a fifth of it. The third colour here is the red.
private func goldAndRed() -> CGImage {
    Pictures.drawn(field: RGB(0xE8, 0xC8, 0x6A), splash: RGB(0x9B, 0x1B, 0x1B), share: 0.2)
}

@Test func aSleeveOfTwoColoursGivesUpBothOfThem() {
    let read = Thumbnail.colours(of: goldAndRed())

    let shade = try! #require(read.shade, "the red on the sleeve was never read")
    #expect(shade.r > shade.g && shade.r > shade.b, "not a red: \(shade)")
}

@Test func aSleeveOfOneColourHasNoThirdToGive() {
    #expect(Thumbnail.colours(of: Pictures.drawn(field: RGB(0xE8, 0xC8, 0x6A))).shade == nil)
}

/// The highlight is scored the same way on its own. Reading all the colours as a list does not
/// change the highlight.
@Test func readingThemAsAListLeavesTheHighlightWhereItWas() {
    let read = Thumbnail.colours(of: goldAndRed())
    let square = try! #require(Thumbnail.square(goldAndRed()))

    #expect(read.highlight == CoverColor.highlight(rgba: square))
}

/// **A disc must be kept as a PNG.** The corners of a disc are transparent. That is what makes it
/// look like a record and not a photograph of one. A JPEG cannot store an alpha channel, so a disc
/// kept in the cover's format would come back from the disk as a full square.
@Test func aDiscIsKeptInAFormatThatCanHoldItsShape() {
    let image = Thumbnail.of(Pictures.disc(RGB(20, 20, 20), edge: 600), edge: Thumbnail.stored)!

    let asDisc = try! #require(Thumbnail.encoded(image, .disc))
    let asCover = try! #require(Thumbnail.encoded(image, .cover))

    let round = try! #require(Thumbnail.of(asDisc, edge: 256))
    let square = try! #require(Thumbnail.of(asCover, edge: 256))

    #expect(Pictures.opacity(of: round, atX: 1, y: 1) == 0)
    #expect(Pictures.opacity(of: square, atX: 1, y: 1) == 255,
            "the sleeve's format grew an alpha channel, so this test proves nothing")
}
