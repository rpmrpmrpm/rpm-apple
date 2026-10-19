import Foundation

/// One line of chrome, and where it sits in its travel.
///
/// The desktop app's `Marquee.cs` does the same job. A line short enough for its column never
/// moves, and it is drawn plainly. A line too long to fit rests at its start. It walks left at
/// reading pace until its tail shows, holds long enough to read the tail, runs back, and rests
/// again.
///
/// **The rest at the start matters most.** The title is there, and a reader looks for the title
/// first.
///
/// The arithmetic is kept here, apart from the drawing. Arithmetic can be wrong without looking
/// wrong. A line that walks past its own tail, or a cycle that does not return to zero, would
/// make a title look broken every time it repeats.
public enum MarqueeWalk {
    /// How long a line rests at its starting position before it moves again.
    public static let startPause: Double = 10

    /// How long it holds at the far end, so that the tail can be read.
    public static let endPause: Double = 2

    /// Reading pace, and the quicker pace of the run back. Both are in points a second. A long
    /// title takes longer to walk than a short one. If every line took the same time, a long
    /// line would move too fast to read.
    public static let pace: Double = 42
    public static let backPace: Double = 130

    /// How far PAST its tail a line walks before it holds. If the last glyph stopped exactly on
    /// the clip's edge, the line would look cut off. A few points of space after the tail show
    /// that the line has ended.
    public static let tailSlack: Double = 10

    /// How far a line has to walk to show its tail. Zero when the line already fits.
    public static func travel(text: Double, column: Double) -> Double {
        max(0, text + tailSlack - column)
    }

    /// How many points of the line are hidden past the column's trailing edge while it sits at
    /// `offset`. Zero once the tail is in view, and zero for a line that fits. The trailing
    /// dissolve is then gone by the time the last letter arrives.
    public static func hiddenAfter(offset: Double, travel: Double) -> Double {
        guard travel > 0 else { return 0 }
        return max(0, travel - tailSlack + offset)
    }

    /// One whole cycle, from start to start.
    public static func period(travel: Double) -> Double {
        guard travel > 0 else { return 0 }
        return startPause + travel / pace + endPause + travel / backPace
    }

    /// Where the line sits `seconds` into its travel. Zero at rest, and negative while it is
    /// walked left.
    public static func offset(at seconds: Double, travel: Double) -> Double {
        guard travel > 0 else { return 0 }

        let cycle = period(travel: travel)
        var at = seconds.truncatingRemainder(dividingBy: cycle)
        if at < 0 { at += cycle }

        if at < startPause { return 0 }
        at -= startPause

        let walking = travel / pace
        if at < walking { return -at * pace }
        at -= walking

        if at < endPause { return -travel }
        at -= endPause

        // Never above zero. The last fraction of a frame before the cycle wraps must not go past
        // zero. If it did, the line would appear to bounce off its own start.
        return min(0, -travel + at * backPace)
    }
}
