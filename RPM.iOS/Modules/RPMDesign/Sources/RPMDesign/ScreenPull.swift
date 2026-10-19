import CoreGraphics

/// A screen raised over the app and put away by pulling it down. This covers the player, the queue
/// drawer, and anything else that arrives from the foot of the screen with a grip at the top of it.
///
/// ## Why the two facts are one value
///
/// Whether such a screen is up, and how far down it has been pulled, are not two pieces of state that
/// happen to sit near each other. **A screen that is up is up at a position, and the position of a
/// screen that has just been raised is the top.** If the two are held apart, they can come apart. Each
/// way they come apart is a fault that someone would have to watch for:
///
/// - The travel outlives the showing. A view that SwiftUI has taken off the screen keeps its `@State`.
///   So a player that was put away at the floor is raised again *at the floor*. It is present and
///   correct, but invisible, and nothing is left for the mini player to turn on.
/// - So the travel has to be put back somewhere, and there is no safe place to do that by hand. Before
///   the removal, the screen is still drawn. A viewer then sees the player standing at the top again at
///   full height for a frame. After the removal, the reset happens in `onDisappear`, which does not run
///   for a screen that is raised again out of its own way out. In a close's completion handler, the
///   reset is worse still. A close that has to finish animating before it happens does not always
///   happen.
///
/// These are not bugs to fix one at a time. They are the same fault: the way out could be left standing
/// while the way in did not say where it started. So ``raise()`` is the only way up, and it states the
/// position. That makes a stale travel impossible to express, not just unlikely.
///
/// ## What draws it
///
/// The value answers the drawing. ``down`` is the offset. ``putDown`` is how far into the putting-down
/// everything keyed off it should be. ``share(of:)`` gives the same thing as a fraction of a panel that
/// knows its own height. Nothing derived from a pull is stored, so nothing derived from a pull can go
/// stale.
///
/// **The screen itself moves only while a hand is on it.** ``putAway()`` leaves the travel exactly where
/// the finger stopped, and it does nothing else. The journey from there to off the bottom belongs to the
/// removal transition. That is one thing carrying the screen, rather than two things taking it to
/// different places on different clocks.
public struct ScreenPull: Equatable, Sendable {
    /// Whether the screen is up. It is written by ``raise()`` and ``putAway()``, and by nothing else.
    /// That is what keeps the pairing true.
    public private(set) var up: Bool

    /// How far down the screen has been pulled, in points from the top. Never negative, because there
    /// is nothing above one of these screens to go to.
    public private(set) var down: CGFloat

    /// Down, and at the top.
    public init() {
        up = false
        down = 0
    }

    /// Raise the screen. This is the only way up, and it states where the screen starts. A screen comes
    /// up at the top, whatever position it went down at.
    public mutating func raise() {
        up = true
        down = 0
    }

    /// Follow a finger, using where it is **now** and where it **began**. Both are read in a space that
    /// this screen does not move. Upward travel is dropped rather than resisted.
    ///
    /// Two readings are used rather than a travel. That is the main guard in this type. A gesture
    /// hands over a translation, and a translation is measured in whatever space the gesture was
    /// declared in. For a grip at the top of a screen that the grip moves, that space travels with the
    /// screen. If a translation were passed in, this would follow a finger to 90 points, move the screen
    /// 90 points, and then be told zero on the next frame. The player would stand in two places every
    /// frame instead of being put away. There is no parameter here that accepts a translation.
    public mutating func follow(to y: CGFloat, from start: CGFloat) {
        down = max(0, y - start)
    }

    /// Back to the top. The hand let go before the screen reached the way out.
    public mutating func home() {
        down = 0
    }

    /// Put the screen away. The travel stays **where the finger left it**, for whatever draws the
    /// going to carry on from there.
    public mutating func putAway() {
        up = false
    }

    // ── what a hand meant ──

    /// How far down is far enough to count as letting go of the screen.
    public static let far: CGFloat = 120

    /// How far the hand is heading, in points, when a throw says the same thing without the screen
    /// having come that far.
    public static let thrown: CGFloat = 260

    /// The travel a drag needs before it counts as a drag at all. A grip also takes a tap, and a few
    /// points of slip under a finger is still a tap.
    public static let slip: CGFloat = 8

    /// Whether a hand that has let go here has let go of the screen. It uses how far the screen has
    /// come (``down``, which the last ``follow(to:from:)`` set) and where the hand was heading when it
    /// stopped. Both are two readings in a space the screen does not move, for the reason given in
    /// ``follow(to:from:)``.
    public func letGo(heading to: CGFloat, from start: CGFloat) -> Bool {
        down > Self.far || to - start > Self.thrown
    }

    // ── what it draws as ──

    /// The first 24 points of travel. Everything that shows "on its way down" grows over this distance,
    /// rather than appearing at once. A drag does not begin until the finger has moved ``slip``. So
    /// anything keyed straight off the travel would jump a third of the way on the first frame anyone
    /// sees.
    public static let ramp: CGFloat = 24

    /// How far into the putting-down the screen is. It is zero at home, one 24 points in, and one for as
    /// long as it is on its way out. **The going is not a flag.** A screen that is not up is leaving.
    /// So anything a leaving screen wears is answered by this value, with no second piece of state to
    /// keep in step. Examples are a corner radius that must not square off half way out, and a key that
    /// must not still be pressable.
    public var putDown: CGFloat {
        up ? min(down / Self.ramp, 1) : 1
    }

    /// The travel as a fraction of a panel that knows its own height. It is zero at home, and one when
    /// the panel is exactly its own height down. This is for the scrim behind a drawer. The scrim has
    /// to go down with the drawer, rather than stay black behind a panel that is already half off the
    /// screen.
    public func share(of height: CGFloat) -> CGFloat {
        guard height > 0 else { return up ? 0 : 1 }

        return min(1, max(0, down / height))
    }
}
