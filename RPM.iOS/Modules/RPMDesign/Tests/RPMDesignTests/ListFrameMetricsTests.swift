import Testing
import CoreGraphics
@testable import RPMDesign

/// Where a generated list's name lands in the frame's band.
///
/// These tests use a made-up face, not a real one. That is the point: they check the arithmetic
/// between the measurements. With a real face, every number here would be a fact about that font.
struct ListFrameMetricsTests {
    /// A face whose letters are a fixed fraction of the size they are set at. Its gauge reaches
    /// further up than down, like an f and a g.
    ///
    /// - Parameters:
    ///   - width: how wide one character is, as a fraction of the size.
    ///   - bearing: how far the ink starts from the pen.
    private func face(width: CGFloat = 0.4, bearing: CGFloat = 0.06)
    -> (String, CGFloat) -> ListFrameMetrics.Ink {
        { said, size in
            guard !said.isEmpty else {
                return ListFrameMetrics.Ink(left: 0, width: 0, top: 0, bottom: 0)
            }

            // The gauge runs from an ascender to a descender. A name with neither is shorter.
            let up: CGFloat = said.contains("f") ? 0.70 : 0.52
            let down: CGFloat = said.contains("g") ? 0.20 : 0

            return ListFrameMetrics.Ink(left: size * bearing,
                                        width: size * width * CGFloat(said.count),
                                        top: -size * up, bottom: size * down)
        }
    }

    private static let edge: CGFloat = 800

    // ── the size ──

    /// The gauge's ink is made as tall as the band, which is `nameCross` of the square's edge.
    /// Every cover then uses the same type size, whatever letters the name has.
    @Test func theTypeIsSizedUntilTheGaugeFillsTheBand() {
        let measure = face()
        let set = ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: measure)!

        let gauge = measure(ListFrameMetrics.gauge, set.size)
        #expect(abs(gauge.height - Self.edge * ListFrameMetrics.nameCross) < 0.001)
    }

    /// **Two names, one size.** The gauge stops names from being set at different sizes. Sized by
    /// their own ink, "Favorite tracks" and "Loved and forgotten" would differ on one shelf,
    /// because only the second has descenders.
    @Test func everyNameIsSetAtTheSameSize() {
        let measure = face()
        let short = ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: measure)!
        let deep = ListFrameMetrics.lettering("Loved and forgotten",
                                              edge: Self.edge, measuring: measure)!

        #expect(abs(short.size - deep.size) < 0.001)
    }

    /// The size is also reduced if the name would run into the app's own name in the corner.
    /// That is the one limit measured from the name itself.
    @Test func aNameTooLongForTheRunIsSetSmaller() {
        let measure = face()
        let ordinary = ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: measure)!
        let endless = ListFrameMetrics.lettering(String(repeating: "n", count: 40),
                                                 edge: Self.edge, measuring: measure)!

        #expect(endless.size < ordinary.size)

        let ink = measure(String(repeating: "n", count: 40), endless.size)
        #expect(ink.width <= Self.edge * ListFrameMetrics.nameRun + 0.001)
    }

    /// A name that fits is left at its size. It is not stretched to fill the run.
    @Test func aNameThatFitsIsNotStretchedToTheRun() {
        let measure = face()
        let set = ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: measure)!

        #expect(measure("Your mix", set.size).width < Self.edge * ListFrameMetrics.nameRun)
    }

    // ── where it sits ──

    /// **Centred on the gauge, not on the name.** Otherwise a name with no descender would sit
    /// lower in the band than one with a descender, and no two covers would share a baseline.
    @Test func everyNameSharesOneBaseline() {
        let measure = face()
        let noTail = ListFrameMetrics.lettering("Favorite tracks",
                                                edge: Self.edge, measuring: measure)!
        let tailed = ListFrameMetrics.lettering("Loved and forgotten",
                                                edge: Self.edge, measuring: measure)!

        #expect(abs(noTail.acrossBand - tailed.acrossBand) < 0.001)
    }

    /// The baseline sits below the middle of the band by the same amount that the gauge reaches
    /// above it. That puts the gauge's ink on the centre line. The value is positive, because y
    /// grows downward.
    @Test func theBaselineIsBelowTheBandsMiddle() {
        let measure = face()
        let set = ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: measure)!
        let gauge = measure(ListFrameMetrics.gauge, set.size)

        #expect(set.acrossBand > 0)
        #expect(abs(set.acrossBand - -((gauge.top + gauge.bottom) / 2)) < 0.001)
    }

    /// The pen moves back by the name's own left bearing, so the ink starts where the run does,
    /// not a bearing into it.
    @Test func theInkStartsWhereTheRunDoes() {
        let measure = face(bearing: 0.2)
        let set = ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: measure)!

        #expect(abs(set.alongBand + measure("Your mix", set.size).left) < 0.001)
    }

    /// The anchor is read from the "rpm" mark in the corner, so the name and the app's mark line up.
    @Test func theAnchorIsOnTheMarkInTheCorner() {
        let anchor = ListFrameMetrics.anchor(edge: 800)

        #expect(abs(anchor.x - 726.5) < 0.5)
        #expect(abs(anchor.y - 30) < 0.5)
    }

    // ── what cannot be set ──

    /// A face with no letters measures nothing. The frame is then drawn with no name, not with a
    /// row of empty boxes.
    @Test func aFaceThatMeasuresNothingSetsNothing() {
        let nothing: (String, CGFloat) -> ListFrameMetrics.Ink = { _, _ in
            ListFrameMetrics.Ink(left: 0, width: 0, top: 0, bottom: 0)
        }

        #expect(ListFrameMetrics.lettering("Your mix", edge: Self.edge, measuring: nothing) == nil)
    }

    /// A face with no Latin letters measures the gauge as nothing, but measures the name. The
    /// name then sets the size. That is better than no name at all.
    @Test func aFaceWithNoLatinIsSizedByTheNameItself() {
        let measure: (String, CGFloat) -> ListFrameMetrics.Ink = { said, size in
            said == ListFrameMetrics.gauge
                ? ListFrameMetrics.Ink(left: 0, width: 0, top: 0, bottom: 0)
                : ListFrameMetrics.Ink(left: 0, width: size * CGFloat(said.count),
                                       top: -size * 0.8, bottom: 0)
        }

        let set = ListFrameMetrics.lettering("你的专属歌单", edge: Self.edge, measuring: measure)

        #expect(set != nil)
        #expect(set!.size > 0)
    }

    /// An empty name, and a square with no size. Both return nil rather than dividing by zero.
    @Test func nothingToSetAndNowhereToSetIt() {
        #expect(ListFrameMetrics.lettering("", edge: Self.edge, measuring: face()) == nil)
        #expect(ListFrameMetrics.lettering("Your mix", edge: 0, measuring: face()) == nil)
    }
}
