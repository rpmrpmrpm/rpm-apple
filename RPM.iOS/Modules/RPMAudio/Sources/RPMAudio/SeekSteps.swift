import Foundation

/// How far the remote's Left and Right buttons move the playhead preview on a focused seek bar:
/// 10 seconds for each press. While a button is held, the speed is at least 30 seconds a second,
/// or fast enough to cross the whole track in 6 seconds, whichever is faster. The seek itself is
/// made once, when the button is released. The same steps are used by the desktop app
/// (`SeekBar.StepBy`) and the Android TV app (`SeekSteps`).
public enum SeekSteps {
    /// The step for one press, in seconds.
    public static let press: Double = 10

    /// While the button is held, the playhead moves at least this many seconds each second.
    public static let heldLeast: Double = 30

    /// The held speed is also fast enough to cross the whole track in this many seconds, if
    /// that is faster.
    public static let heldCross: Double = 6

    /// The longest gap (in seconds) between two steps that a held step counts. The first
    /// repeat arrives some time after the press, and counting that whole delay would make
    /// the playhead jump.
    public static let heldGap: Double = 0.25

    /// Where one step moves the playhead from `from`, limited to 0 and `duration` (seconds).
    /// - Parameters:
    ///   - way: -1 for Left, 1 for Right.
    ///   - held: whether the key is held and this is one of its repeats.
    ///   - since: the time since the previous step, in seconds.
    public static func next(from: Double, way: Int, held: Bool, since: Double, duration: Double) -> Double {
        let by = held
            ? max(heldLeast, duration / heldCross) * min(max(since, 0), heldGap)
            : press
        return min(max(from + Double(way) * by, 0), max(duration, 0))
    }
}
