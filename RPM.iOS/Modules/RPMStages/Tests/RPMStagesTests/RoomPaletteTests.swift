import Foundation
import Testing
@testable import RPMStages

/// The four colours a room is painted in.
///
/// **Two of these tests are regression cases.** A gold sleeve lit a green room, and a
/// pink-and-yellow one lit an orange room. Both faults came from turning a hue to invent a
/// colour that was not on the cover. They are written as cases because a rule that stops a
/// specific wrong answer should be pinned by that answer.
@Suite("The four colours a room is painted in")
struct RoomPaletteTests {

    // Sleeve colours, roughly as a cover would give them up.
    let gold = SIMD3<Float>(0.72, 0.55, 0.13)
    let red = SIMD3<Float>(0.63, 0.11, 0.09)
    let navy = SIMD3<Float>(0.10, 0.13, 0.28)
    let pink = SIMD3<Float>(0.90, 0.42, 0.62)
    let yellow = SIMD3<Float>(0.93, 0.83, 0.20)
    let brown = SIMD3<Float>(0.36, 0.28, 0.20)

    /// How far apart two colours are as directions, the same question `same` asks.
    func apart(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        func unit(_ c: SIMD3<Float>) -> SIMD3<Float> {
            let n = (c * c).sum().squareRoot()
            return n > 1e-4 ? c / n : .zero
        }
        let d = unit(a) - unit(b)
        return (d * d).sum().squareRoot()
    }

    /// Whether a colour is greenish, orangeish and so on: enough to say a room is the wrong
    /// colour, which is all these tests need.
    func isGreen(_ c: SIMD3<Float>) -> Bool { c.y > c.x * 1.15 && c.y > c.z * 1.15 }
    func isOrange(_ c: SIMD3<Float>) -> Bool { c.x > c.y * 1.25 && c.y > c.z * 1.5 }

    // ── the two records ──

    /// **1991.** A gold sleeve with red hair and black gloves: its dominant tone and its accent
    /// are both gold, so the hue rotation applies, and forty degrees from gold is green. That
    /// would give a green room for a record with no green on it. The red is on the sleeve, one
    /// slot along.
    @Test func aOneColourSleeveTakesItsSecondColourFromTheSleeve() {
        let room = RoomPalette.from(tint: gold, glow: gold, shade: red)

        #expect(!isGreen(room.glow), "the room went green: \(room.glow)")

        // And it is the red that was on the sleeve, not an invented colour.
        #expect(apart(room.glow, red) < 0.3,
                "the accent is \(room.glow), which is not the sleeve's red")
    }

    /// A sleeve of one colour keeps that colour for the tint and the glow, and the shade is
    /// grey. No hue is turned to make a second colour.
    @Test func aSleeveOfOneColourAndNothingElseGetsAGreyShade() {
        let room = RoomPalette.from(tint: gold, glow: gold, shade: nil)

        #expect(RoomPalette.same(room.glow, gold), "the glow is \(room.glow), not the sleeve's gold")
        #expect(room.shade == RoomPalette.shadeGrey, "the shade is \(room.shade), not grey")
    }

    /// A red, orange or brown sleeve with no third colour must not light the second family
    /// green or teal. The shade must not be the dominant tone turned by 152°.
    @Test func aWarmSleeveWithNoThirdColourPutsNoGreenOnScreen() {
        for sleeve in [red, brown, gold, pink] {
            let room = RoomPalette.from(tint: sleeve, glow: sleeve, shade: nil)

            for colour in [room.tint, room.glow, room.shade] {
                #expect(!isGreen(colour), "\(colour) is green, from \(sleeve)")
            }
        }
    }

    /// **Pink and yellow.** The dominant tone of that cover is the dark navy of the figure, and
    /// 150 degrees from navy is orange, which is not on the record. A cover of pink and yellow
    /// should put pink and yellow on the screen.
    @Test func aSleeveWithAThirdColourWearsItRatherThanAnInventedOne() {
        let room = RoomPalette.from(tint: navy, glow: pink, shade: yellow)

        #expect(!isOrange(room.shade), "the second family went orange: \(room.shade)")
        #expect(apart(room.shade, yellow) < 0.3,
                "the shade is \(room.shade), which is not the sleeve's yellow")
    }

    // ── the colours themselves ──

    /// **A room painted in a cover's dominant tone is a brown room.** What is wanted is the
    /// colour the eye sees on the sleeve, which is that tone at the saturation people remember.
    @Test func aMuddyToneIsLitRatherThanPaintedAsItIs() {
        let room = RoomPalette.from(tint: brown, glow: brown, shade: nil)

        let before = max(brown.x, max(brown.y, brown.z))
        let after = max(room.tint.x, max(room.tint.y, room.tint.z))

        #expect(after > before, "the mud stayed mud: \(before) to \(after)")

        // The hue survives being lit, or it is a different record's colour.
        #expect(room.tint.x > room.tint.y && room.tint.y > room.tint.z,
                "it stopped being a warm colour: \(room.tint)")
    }

    /// A sleeve with nothing to give keeps the app's own blue and does not go black.
    @Test func aSleeveWithNoColourKeepsTheAppsOwnBlue() {
        #expect(RoomPalette.from(tint: nil, glow: nil, shade: nil) == .fallback)
    }

    /// One colour is enough: each of the two stands in for the other.
    @Test func eitherOneOfTheTwoIsEnoughOnItsOwn() {
        #expect(RoomPalette.from(tint: pink, glow: nil, shade: nil) != .fallback)
        #expect(RoomPalette.from(tint: nil, glow: pink, shade: nil) != .fallback)
    }

    /// The ground still belongs to the record, but never competes with it.
    @Test func theGroundBelongsToTheRecordWithoutCompetingWithIt() {
        let room = RoomPalette.from(tint: pink, glow: yellow, shade: nil)

        let ground = max(room.ground.x, max(room.ground.y, room.ground.z))
        let tint = max(room.tint.x, max(room.tint.y, room.tint.z))

        #expect(ground < tint * 0.5, "the ground is as loud as the figures on it")
        #expect(ground > 0.02, "the ground went to pure black and stopped being the record's")
    }

    /// Every colour is a colour: nothing out of range, whatever the sleeve hands over.
    @Test func everyColourStaysInRange() {
        for sleeve in [gold, red, navy, pink, yellow, brown, .zero, SIMD3<Float>(repeating: 1)] {
            let room = RoomPalette.from(tint: sleeve, glow: sleeve, shade: sleeve)

            for colour in [room.ground, room.tint, room.glow, room.shade] {
                #expect(colour.min() >= 0 && colour.max() <= 1, "\(colour) from \(sleeve)")
            }
        }
    }

    // ── the arithmetic underneath ──

    /// **Compared as directions**, so a light colour and a dark one of the same hue count as
    /// one colour. That is the question being asked, since two families painted in those would
    /// look like a single family however far apart their values are.
    @Test func aLightColourAndADarkOneOfTheSameHueAreOneColour() {
        #expect(RoomPalette.same(pink, pink * 0.3), "a dark pink is still pink")
        #expect(!RoomPalette.same(pink, yellow), "pink and yellow are two colours")
    }

    // ── the dissolve ──

    /// A track change is a dissolve, not a cut, and it completes.
    @Test func onePaletteEasesIntoAnother() {
        let from = RoomPalette.from(tint: navy, glow: pink, shade: yellow)
        let to = RoomPalette.from(tint: gold, glow: red, shade: nil)

        var at = from
        for _ in 0..<200 { at = at.eased(to: to, by: 0.05) }

        #expect(apart(at.tint, to.tint) < 0.01, "it never arrived")

        // And a single step moves, but only part of the way.
        let one = from.eased(to: to, by: 0.05)
        #expect(one != from, "it did not move at all")
        #expect(apart(one.tint, to.tint) > 0.01, "it jumped rather than eased")
    }
}
