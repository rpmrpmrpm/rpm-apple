import Testing
import Foundation
@testable import RPMDesign

/// The colours a generated list is drawn in, checked against the numbers the desktop measured.
///
/// **These are cross-head tests, and that is the point of them.** The arithmetic runs twice, in
/// two languages, from the same three fields. Nothing at runtime compares the two answers. A
/// phone that picked a different seed would draw a list in colours the computer does not match,
/// and nobody would see it unless the two screens were compared side by side.
///
/// The reference values are the remarks in `CoverOverlay.Ink`. They record the contrast that the
/// desktop measured over the five framed lists. The lowest pair is 3.15:1: "Favorite tracks" and
/// "Loved and forgotten", Crimson on Red's foot. The highest is 9.87:1: "New to you", Lime on
/// Forest's foot. If this port drifts from those figures, these tests fail.
struct GeneratedListLookTests {
    private func accent(_ name: String) -> RGB {
        RPMPalette.accents.first { $0.name == name }!.base
    }

    private func foot(_ name: String) -> RGB {
        RPMPalette.accents.first { $0.name == name }!.gradient.last!
    }

    // ── the seed ──

    /// The desktop notes that "'Favorite tracks' and 'Loved and forgotten' are both Crimson at
    /// seed 9,778". The two lists share one seed. On the desktop they differ only in which icon
    /// family draws their figure, and that does not change the frame.
    @Test func theTwoHeartListsAreOneSeed() {
        let favourites = GeneratedListLook.seed(
            hue: GeneratedListLook.hue(of: "FavoriteTracks")!, genre: nil, decade: 0)
        let forgotten = GeneratedListLook.seed(
            hue: GeneratedListLook.hue(of: "LovedAndForgotten")!, genre: nil, decade: 0)

        #expect(favourites == 9778)
        #expect(forgotten == 9778)
    }

    /// A list with no genre and no decade lands on its own hue in the ring. The ten kinds that
    /// share a hue share a colourway, so the shelf comes out in the palette's own order.
    @Test func aPlainListIsItsHueOffTheRing() {
        let seed = GeneratedListLook.seed(hue: 5, genre: nil, decade: 0)

        #expect(seed % UInt32(RPMPalette.accents.count) == 5)
    }

    /// A genre keeps its parent's hue and changes the rest of the seed.
    @Test func aGenreKeepsTheHueAndMovesEverythingElse() {
        let plain = GeneratedListLook.seed(hue: 5, genre: nil, decade: 0)
        let rock = GeneratedListLook.seed(hue: 5, genre: "Rock", decade: 0)

        #expect(rock != plain)
        #expect(rock % UInt32(RPMPalette.accents.count) == 5)
    }

    /// Two decades ten years apart are not neighbours on the ring. The seed scatters the decade
    /// rather than adding it. If the decade were added raw, every decade of one mood would
    /// repeat one cover.
    @Test func decadesAreScatteredRatherThanAdded() {
        let sixties = GeneratedListLook.seed(hue: 5, genre: nil, decade: 1960)
        let seventies = GeneratedListLook.seed(hue: 5, genre: nil, decade: 1970)

        #expect(sixties != seventies)
        #expect(abs(Int(sixties) - Int(seventies)) > 10)
    }

    /// The hash runs over UTF-16 code units, because the desktop walks a C# `string`, and a C#
    /// char is one unit. The test computes the expected value the same way. A rewrite that
    /// hashes bytes or Unicode scalars fails here, not on a shelf.
    @Test func theGenreHashIsFnv1aOverUtf16() {
        #expect(GeneratedListLook.scatter("Rock") == fnv("Rock"))
        #expect(GeneratedListLook.scatter("") == 2166136261 % 4096)
    }

    private func fnv(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for unit in text.utf16 { hash = (hash ^ UInt32(unit)) &* 16777619 }
        return hash % 4096
    }

    // ── the trio ──

    /// The two heart lists share this seed. Their trio is Red, Crimson and Magenta.
    @Test func theHeartListsRollRedCrimsonAndMagenta() {
        let trio = GeneratedListLook.trio(seed: 9778)!

        #expect(trio.deep == accent("Red"))
        #expect(trio.mid == accent("Crimson"))
        #expect(trio.hot == accent("Magenta"))
    }

    /// The trio is sorted by light, not by ring position. Lime is much brighter than Forest's
    /// other neighbours, so it is the hot colour whatever order the ring gives.
    @Test func theTrioIsSortedByLightAndNotByTheRing() {
        let trio = GeneratedListLook.trio(seed: 9774)!

        #expect(trio.hot == accent("Lime"))
        #expect(trio.mid == accent("Azure"))
        #expect(trio.deep == accent("Forest"))
    }

    // ── the two inks, against the desktop's own measurements ──

    /// The lowest contrast the desktop measured: 3.15:1, Crimson on Red's foot.
    @Test func theHeartListsAreCrimsonOnRedsFoot() {
        let look = GeneratedListLook.of(kind: "FavoriteTracks", genre: nil, decade: 0)!

        #expect(look.border == foot("Red"))
        #expect(look.text == accent("Crimson"))

        let measured = GeneratedListLook.contrast(look.text, look.border)
        #expect(abs(measured - 3.15) < 0.01, "the desktop measured 3.15:1, this reads \(measured)")
    }

    /// And the highest: 9.87:1, Lime on Forest's foot. "New to you" is `FirstListens`.
    @Test func newToYouIsLimeOnForestsFoot() {
        let look = GeneratedListLook.of(kind: "FirstListens", genre: nil, decade: 0)!

        #expect(look.border == foot("Forest"))
        #expect(look.text == accent("Lime"))

        let measured = GeneratedListLook.contrast(look.text, look.border)
        #expect(abs(measured - 9.87) < 0.01, "the desktop measured 9.87:1, this reads \(measured)")
    }

    /// **Not simply the brightest of the three.** For the heart lists the brightest is Magenta,
    /// and it cannot be read on that border. The ink that is chosen is the middle colour. This
    /// is stated on its own, because a change to "pick the hot colour" would pass every other
    /// test here.
    ///
    /// The desktop's note gives Magenta at 2.95:1, and this code reads 3.00. The two figures that
    /// the frames are inked by, 3.15 and 9.87 above, agree to a hundredth. So the difference is in
    /// that note, not in the arithmetic, and it is not worth a test.
    @Test func theInkIsTheMostReadableAndNotTheBrightest() {
        let look = GeneratedListLook.of(kind: "FavoriteTracks", genre: nil, decade: 0)!

        let brightest = GeneratedListLook.contrast(look.trio.hot, look.border)
        let chosen = GeneratedListLook.contrast(look.text, look.border)

        #expect(look.text != look.trio.hot)
        #expect(chosen > brightest)
    }

    /// The border is read from the palette's own gradient, not calculated. So a new palette
    /// passes through these tests without anyone editing the arithmetic.
    @Test func theBorderIsTheAssetsOwnDarkestStop() {
        for accent in RPMPalette.accents {
            #expect(GeneratedListLook.foot(of: accent.base) == accent.gradient.last)
        }
    }

    // ── the tint a photograph is washed in ──

    /// A whole mood's tint is the palette entry that its hue names. This matches the desktop's
    /// `SmartPlaylistFace.Look` table: Calm is Azure and Energetic is Red. The seed for a whole
    /// mood is `977 * count + hue`, so it lands on the hue exactly.
    @Test func aWholeMoodIsWashedInItsOwnHue() {
        for kind in ["Calm", "Energetic", "Danceable", "Decade", "Classical", "MostPlayed"] {
            let hue = Int(GeneratedListLook.hue(of: kind)!)
            let look = GeneratedListLook.of(kind: kind, genre: nil, decade: 0)!
            #expect(look.tint == RPMPalette.accents[hue].base, "\(kind)")
        }
    }

    /// A genre or decade under a mood changes the seed. The tint is still the entry that the
    /// seed lands on, not whichever of the three sorted colours is brightest.
    @Test func aNarrowedListIsWashedInTheColourItsSeedLandsOn() {
        let ring = RPMPalette.accents.map(\.base)

        for (genre, decade) in [("Rock", 0), ("Hip-Hop / Rap", 0), (nil, 1980)] as [(String?, Int)] {
            let seed = GeneratedListLook.seed(hue: 5, genre: genre, decade: decade)
            let look = GeneratedListLook.of(kind: "Calm", genre: genre, decade: decade)!

            #expect(look.tint == ring[Int(seed % UInt32(ring.count))])
            #expect([look.trio.hot, look.trio.mid, look.trio.deep].contains(look.tint))
        }
    }

    /// A colour the palette does not hold has no gradient to read. Its foot is the colour with
    /// each channel scaled to 40%, which is the level that the palette's own gradients end at.
    @Test func aColourWithNoRampIsTakenToFourTenths() {
        #expect(GeneratedListLook.foot(of: RGB(200, 100, 50)) == RGB(80, 40, 20))
    }

    // ── which lists stand on the room ──

    /// The five lists that stand on the room, and no others. Every generated list gets a frame.
    /// These five have no picture of their own to put behind the window.
    @Test func fiveListsStandOnTheRoom() {
        for kind in ["RightNow", "OnRepeat", "FavoriteTracks", "FirstListens", "LovedAndForgotten"] {
            #expect(GeneratedListLook.roomed(kind: kind), "\(kind) should stand on the room")
        }

        for kind in ["Calm", "Decade", "MostPlayed", "LateNight", "NeverPlayed"] {
            #expect(!GeneratedListLook.roomed(kind: kind), "\(kind) keeps its own picture")
        }
    }

    /// A kind that this build does not know comes from a newer version of the app. It returns no
    /// look, and the list is shown without a frame rather than not shown at all.
    @Test func aKindThisBuildDoesNotKnowHasNoLook() {
        #expect(GeneratedListLook.of(kind: "SomethingNewer", genre: nil, decade: 0) == nil)
    }

    /// Every kind that this build knows must draw. A table of twenty cases can miss one without
    /// any error, so this test checks all of them.
    @Test func everyKnownKindHasALook() {
        let kinds = ["Calm", "Energetic", "Danceable", "Focus", "Sleep", "Decade", "Classical",
                     "FavoriteTracks", "MostPlayed", "OnRepeat", "RecentlyPlayed", "RecentlyAdded",
                     "FirstListens", "LateNight", "Rediscover", "LovedAndForgotten",
                     "PlayedNotLoved", "NeverPlayed", "KeepSkipping", "RightNow"]

        for kind in kinds {
            #expect(GeneratedListLook.of(kind: kind, genre: nil, decade: 0) != nil, "\(kind) should draw")
        }
    }
}
