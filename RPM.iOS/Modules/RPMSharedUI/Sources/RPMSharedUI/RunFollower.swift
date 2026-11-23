import Foundation

/// The run of bars as it is drawn: it follows the reading by the time that has passed, not by the
/// number of frames.
///
/// **Why the bars need this on top of ``RoomRamp``.** The ramp joins two readings with a straight
/// line, so a bar's position has no jumps. But its speed changes at once at every reading, forty
/// times a second, and a reading often turns a bar from rising to falling. A frame of the display
/// lies across those changes in a different way each time, so one frame moves a bar far and the
/// next one hardly at all. That is seen as a jitter. This follower smooths the speed as well:
/// each frame closes a share of the distance to the ramp, and the share depends on the time since
/// the last frame. So the motion is the same on a 60 Hz and a 120 Hz screen, and on a frame that
/// comes late.
///
/// A bar rises faster than it falls, so a kick still shows at once and the fall is smooth.
///
/// It is read and written while the frame is built, on the main actor, and it is not observed:
/// a new value must not ask for another frame.
@MainActor
public final class RunFollower {
    /// The time constants, in seconds, for a bar that rises and for one that falls. After one
    /// time constant a bar has closed about two thirds of the distance to the reading.
    public static let rise: Double = 0.012
    public static let fall: Double = 0.030

    /// The longest step that one frame is given. After a pause (a sheet that was hidden, a room
    /// that rested) the bars go straight to the reading, and do not travel from a picture that is
    /// seconds old.
    private static let longestStep: Double = 0.1

    private var shown: [Float] = []
    private var last: Double = 0

    /// Creating a follower does no work, so a view can hold it in `@State`. See ``RoomReader``.
    public nonisolated init() {}

    /// The run to draw at `now`, given the run the ramp reads at `now`. `now` is in seconds on a
    /// monotonic clock (`CACurrentMediaTime`), the clock the ramp is read with.
    ///
    /// SwiftUI can build a frame more than once, so this can be called twice for one instant.
    /// The second call then has no time to move the bars and returns the same run.
    public func follow(_ target: [Float], at now: Double) -> [Float] {
        // A run of another length is a new run (the first reading after the engine named its
        // rate, or silence): take it whole.
        guard shown.count == target.count, now - last < Self.longestStep else {
            shown = target
            last = now
            return shown
        }

        let step = max(0, now - last)
        last = now
        guard step > 0 else { return shown }

        let up = Float(1 - exp(-step / Self.rise))
        let down = Float(1 - exp(-step / Self.fall))

        for band in shown.indices {
            let to = target[band]
            shown[band] += (to - shown[band]) * (to > shown[band] ? up : down)
        }

        return shown
    }
}
