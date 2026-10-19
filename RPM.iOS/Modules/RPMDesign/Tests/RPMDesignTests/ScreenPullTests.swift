import Testing
import CoreGraphics
@testable import RPMDesign

/// The faults these tests cover all share one cause: a travel that outlived the showing it
/// belonged to. Each test covers one way that fault showed on the screen.
@Suite("A screen pulled down")
struct ScreenPullTests {
    @Test("starts down, at the top")
    func starts() {
        let pull = ScreenPull()

        #expect(!pull.up)
        #expect(pull.down == 0)
    }

    /// A screen that was put away with a travel of 600 must come up at the top when it is raised
    /// again. Otherwise a tap on the mini player would raise the player at the floor, out of sight.
    @Test("comes up at the top, whatever it went down on")
    func raiseHomes() {
        var pull = ScreenPull()
        pull.raise()
        pull.follow(to: 600, from: 0)
        pull.putAway()

        #expect(pull.down == 600, "the way out leaves the travel where the finger left it")

        pull.raise()

        #expect(pull.up)
        #expect(pull.down == 0)
    }

    @Test("follows a finger down and not up")
    func follows() {
        var pull = ScreenPull()
        pull.raise()

        pull.follow(to: 290, from: 200)
        #expect(pull.down == 90)

        pull.follow(to: 80, from: 200)
        #expect(pull.down == 0, "there is nothing above one of these screens to go to")
    }

    @Test("goes home when the hand lets go short of the way out")
    func home() {
        var pull = ScreenPull()
        pull.raise()
        pull.follow(to: 90, from: 0)
        pull.home()

        #expect(pull.up)
        #expect(pull.down == 0)
    }

    @Test("is let go of by distance or by a throw")
    func letGo() {
        func held(at travelled: CGFloat) -> ScreenPull {
            var pull = ScreenPull()
            pull.raise()
            pull.follow(to: 200 + travelled, from: 200)
            return pull
        }

        #expect(!held(at: 40).letGo(heading: 260, from: 200))
        #expect(held(at: 200).letGo(heading: 410, from: 200), "far enough on its own")
        #expect(held(at: 30).letGo(heading: 600, from: 200), "a flick that was heading there")
        #expect(!held(at: 120).letGo(heading: 460, from: 200), "the thresholds are exclusive")
    }

    /// The travel is never read from the drag's own `translation`. That value is in the coordinate
    /// space of the view the gesture is attached to. That view is a grip inside the thing being
    /// dragged, so once the screen moves, the value reads zero. The screen then flickers between
    /// two positions every frame.
    ///
    /// This test checks the shape that rules that out. The travel is the difference between two
    /// readings the caller supplies. A finger going steadily down the window then gives a steadily
    /// growing pull, however far the screen has moved.
    @Test("takes two readings, so the screen's own travel is nowhere in the answer")
    func twoReadings() {
        var pull = ScreenPull()
        pull.raise()

        // The finger moves down the window in steps of forty points. The screen follows it exactly,
        // but those moves are not in these numbers. That is intended.
        for step in 0...4 {
            let finger = 200 + CGFloat(step) * 40
            pull.follow(to: finger, from: 200)

            #expect(pull.down == CGFloat(step) * 40)
        }
    }

    /// Once the screen is on its way out, `putDown` stays at 1. The corners keep their full radius
    /// for the whole way out. If the travel were reset first, the corners would square off halfway
    /// out.
    @Test("reads as fully put down for as long as it is on its way out")
    func leaving() {
        var pull = ScreenPull()
        pull.raise()

        #expect(pull.putDown == 0)

        pull.follow(to: 12, from: 0)
        #expect(pull.putDown == 0.5, "half an inch in is half way into the ramp")

        pull.follow(to: 400, from: 0)
        #expect(pull.putDown == 1)

        pull.putAway()
        #expect(pull.putDown == 1)

        // This includes a way out with no travel: a tap on the grip.
        var tapped = ScreenPull()
        tapped.raise()
        tapped.putAway()

        #expect(tapped.down == 0)
        #expect(tapped.putDown == 1, "a screen that is not up is leaving, travel or no travel")
    }

    @Test("answers as a share of a panel that knows its own height")
    func share() {
        var pull = ScreenPull()
        pull.raise()

        #expect(pull.share(of: 520) == 0)

        pull.follow(to: 260, from: 0)
        #expect(pull.share(of: 520) == 0.5)

        pull.follow(to: 900, from: 0)
        #expect(pull.share(of: 520) == 1, "and no further")
    }

    /// A height of zero means the panel has not been measured yet. Dividing by zero has no answer,
    /// so this case is stated explicitly.
    @Test("says home for a panel with no height yet")
    func unmeasured() {
        var pull = ScreenPull()
        pull.raise()
        pull.follow(to: 200, from: 0)

        #expect(pull.share(of: 0) == 0)

        pull.putAway()
        #expect(pull.share(of: 0) == 1, "and gone once it is going")
    }
}
