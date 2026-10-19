import Testing
import Foundation
@testable import RPMDesign

/// The desktop code has no tests for `CoverColor`. These tests check the behaviour that the
/// code comments describe, because those comments are the only specification there is.

/// A cover as RGBA bytes: a field of one colour with a splash of another over part of it.
/// Most covers look like this.
private func sleeve(
    _ field: RGB, splash: RGB? = nil, splashShare: Double = 0, pixels: Int = 48 * 48
) -> [UInt8] {
    let splashCount = Int(Double(pixels) * splashShare)

    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixels * 4)

    for i in 0..<pixels {
        let colour = (i < splashCount ? splash : field) ?? field
        bytes.append(contentsOf: [colour.r, colour.g, colour.b, 255])
    }
    return bytes
}

// ── the dominant ──

@Test func aSleeveOfOneColourIsThatColour() {
    let found = CoverColor.dominant(rgba: sleeve(RGB(180, 60, 40)))
    #expect(found == RGB(180, 60, 40))
}

/// Half one colour, half another: the colour seen first in the pixels wins, as on the
/// desktop, whichever of the two it is. Swift randomises dictionary order per process, so
/// the tie must not depend on that order.
@Test func aTieGoesToTheColourSeenFirst() {
    let red = RGB(180, 60, 40), blue = RGB(40, 60, 180)

    #expect(CoverColor.dominant(rgba: sleeve(red, splash: blue, splashShare: 0.5)) == blue)
    #expect(CoverColor.dominant(rgba: sleeve(blue, splash: red, splashShare: 0.5)) == red)
}

/// Many covers are mostly black. Near-black is not picked as the colour of a record, because
/// that is true of many records and tells the reader very little about any one of them.
@Test func nearBlackIsNotWhatARecordIs() {
    let mostlyBlack = sleeve(RGB(4, 4, 4), splash: RGB(200, 40, 60), splashShare: 0.2)
    let found = try! #require(CoverColor.dominant(rgba: mostlyBlack))

    #expect(found.r > 150, "the black field won: \(found)")
}

@Test func nearWhiteIsNotWhatARecordIsEither() {
    let mostlyWhite = sleeve(RGB(250, 250, 250), splash: RGB(40, 90, 200), splashShare: 0.2)
    let found = try! #require(CoverColor.dominant(rgba: mostlyWhite))

    #expect(found.b > 150, "the white field won: \(found)")
}

@Test func aSleeveOfNothingButBlackHasNoColourToGive() {
    #expect(CoverColor.dominant(rgba: sleeve(RGB(2, 2, 2))) == nil)
}

/// Each colour channel has 32 levels, so near-identical pixels count as one colour. A
/// photograph does not return a thousand shades of one colour.
@Test func nearIdenticalPixelsCountAsOneColour() {
    var noisy: [UInt8] = []
    for i in 0..<(48 * 48) {
        // Each pixel differs by 0 to 3 from the others, all inside one bucket.
        let jitter = UInt8(i % 4)
        noisy.append(contentsOf: [160 + jitter, 70 + jitter, 50 + jitter, 255])
    }

    let found = try! #require(CoverColor.dominant(rgba: noisy))
    #expect(abs(Int(found.r) - 161) <= 3, "the buckets split: \(found)")
}

// ── the highlight ──

/// **Scoring is used instead of counting.** A small patch of vivid colour beats a large area
/// of grey or brown. The accent is what a cover is known by, not the dull colour that fills
/// most of it.
@Test func aSmallSplashOfColourBeatsALargeFieldOfBrown() {
    let mud = sleeve(RGB(96, 82, 70), splash: RGB(230, 30, 40), splashShare: 0.08)

    let dominant = try! #require(CoverColor.dominant(rgba: mud))
    let highlight = try! #require(CoverColor.highlight(rgba: mud))

    // The brown really is most of it.
    #expect(dominant.r < 130 && dominant.g < 110)
    // And the red is what the record looks like.
    #expect(highlight.r > 200 && highlight.g < 80)
}

/// The square root makes the count weigh less than the area: a bucket ten times the size
/// counts about three times as much. So a vivid colour that covers a twentieth of the cover
/// still wins against a dull colour that fills the rest.
@Test func theCountIsANodRatherThanAVote() {
    let mostlyDull = sleeve(RGB(110, 105, 100), splash: RGB(240, 20, 20), splashShare: 0.05)
    let highlight = try! #require(CoverColor.highlight(rgba: mostlyDull))
    #expect(highlight.r > 200)
}

/// A black-and-white press photo has no colour to give. Returning nil is the correct answer,
/// not an error. `tint` then falls back to the dominant colour, which for a grey photograph
/// is a grey.
@Test func aGreyCoverHasNoHighlight() {
    let greys = sleeve(RGB(90, 90, 92), splash: RGB(170, 170, 172), splashShare: 0.4)
    #expect(CoverColor.highlight(rgba: greys) == nil)
}

@Test func aVeryDarkCoverHasNoHighlight() {
    #expect(CoverColor.highlight(rgba: sleeve(RGB(20, 6, 6))) == nil)
}

// ── the two together ──

@Test func aTintIsTheHighlightWhereThereIsOne() {
    let mud = sleeve(RGB(96, 82, 70), splash: RGB(230, 30, 40), splashShare: 0.08)
    #expect(CoverColor.tint(rgba: mud) == CoverColor.highlight(rgba: mud))
}

/// Where the cover has no vivid colour at all, the tint is the dominant colour.
@Test func aTintFallsBackToTheDominantWhenNothingIsVivid() {
    let greys = sleeve(RGB(90, 90, 92), splash: RGB(170, 170, 172), splashShare: 0.4)

    #expect(CoverColor.highlight(rgba: greys) == nil)
    #expect(CoverColor.tint(rgba: greys) == CoverColor.dominant(rgba: greys))
}

@Test func aSleeveThatSaysNothingTintsNothing() {
    #expect(CoverColor.tint(rgba: sleeve(RGB(1, 1, 1))) == nil)
}

@Test func noPixelsIsNoColour() {
    #expect(CoverColor.tint(rgba: []) == nil)
    #expect(CoverColor.dominant(rgba: [1, 2, 3]) == nil)
}

// ── it has to be the same answer twice ──

/// Swift randomises dictionary iteration per process, and the highlight is picked by scoring
/// every bucket. Two buckets with the same score would otherwise resolve differently on two
/// runs of the same library. A wall that changes colour between launches is worse than one
/// that picks the wrong colour every time.
@Test func theSameSleeveAlwaysReadsTheSameColour() {
    let mixed = sleeve(RGB(120, 40, 160), splash: RGB(40, 160, 120), splashShare: 0.5)

    let answers = (0..<20).map { _ in CoverColor.tint(rgba: mixed) }
    #expect(Set(answers.map { "\($0!)" }).count == 1, "read \(Set(answers.map { "\($0!)" }))")
}

/// The wall snaps the colour to an accent too, so the whole path from pixels to an accent
/// gives one answer.
@Test func aSleeveSnapsToAnAccent() {
    let red = sleeve(RGB(60, 40, 40), splash: RGB(225, 30, 25), splashShare: 0.1)
    let tint = try! #require(CoverColor.tint(rgba: red))
    let accent = try! #require(RPMPalette.nearest(to: tint))

    #expect(["Vermilion", "Red", "Crimson", "Rust"].contains(accent.name),
            "a red sleeve came out \(accent.name)")
}

// ── the list ──
//
// The list gives the colours that the room is painted from. A gold cover with red lettering
// lit a green room. When the cover has only one colour, `RoomPalette` turns the hue by 42
// degrees to make a second colour. From gold, 42 degrees is green.

/// The test cover: a field of gold with red lettering across a fifth of it.
private let goldAndRed = sleeve(RGB(0xE8, 0xC8, 0x6A), splash: RGB(0x9B, 0x1B, 0x1B),
                                splashShare: 0.2)

@Test func theFirstColourIsTheHighlight() {
    let listed = CoverColor.palette(rgba: goldAndRed, count: 2)
    #expect(listed.first == CoverColor.highlight(rgba: goldAndRed))
}

/// The one that matters: the red is on the cover, so the red must come back.
@Test func theSecondColourIsTheOtherColourOnTheSleeve() {
    let listed = CoverColor.palette(rgba: goldAndRed, count: 2)

    let second = try! #require(listed.count > 1 ? listed[1] : nil,
                               "a gold-and-red sleeve gave up only one colour: \(listed)")
    #expect(second.r > second.g && second.r > second.b, "not a red: \(second)")
}

/// Colours are compared as directions. A light red and a dark red count as one colour, so the
/// list does not use both of its slots on the same colour.
@Test func aLightAndADarkOfOneHueCountAsOneColour() {
    let twoReds = sleeve(RGB(0xC0, 0x30, 0x30), splash: RGB(0x60, 0x18, 0x18),
                         splashShare: 0.4)
    #expect(CoverColor.palette(rgba: twoReds, count: 2).count == 1)
}

@Test func aSleeveOfOneColourGivesUpOneColour() {
    #expect(CoverColor.palette(rgba: sleeve(RGB(0xE8, 0xC8, 0x6A)), count: 3).count == 1)
}

@Test func aSleeveWithNoColourAtAllGivesUpNone() {
    #expect(CoverColor.palette(rgba: sleeve(RGB(8, 8, 8)), count: 2).isEmpty)
}

@Test func askingForNoneGivesNone() {
    #expect(CoverColor.palette(rgba: goldAndRed, count: 0).isEmpty)
}

/// The buckets come from a dictionary, and Swift randomises its order per process. The list
/// must be ordered on purpose, or one library would show two different lists.
@Test func theSameSleeveIsReadTheSameWayTwice() {
    let once = CoverColor.palette(rgba: goldAndRed, count: 2)
    let again = CoverColor.palette(rgba: goldAndRed, count: 2)
    #expect(once == again)
}
