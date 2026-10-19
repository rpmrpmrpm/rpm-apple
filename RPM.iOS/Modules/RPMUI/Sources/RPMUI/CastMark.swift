import SwiftUI
import RPMDesign

/// The cast mark: a screen with arcs coming out of its corner.
///
/// It is Google's icon from Material Icons (Apache 2.0). The desktop and Uno apps use the same
/// two paths. **It is drawn as a path and not taken from a font, because Font Awesome has no
/// cast icon.** A speaker would be wrong here: a speaker shows where sound comes from, and
/// this key shows where it is going.
///
/// The outline is `cast` and the filled screen is `cast_connected`. Together they show
/// whether a room is listening.
struct CastMark: Shape {
    /// Whether a room is connected. The screen is filled when it is.
    let live: Bool

    /// Both paths use Material's 24-unit box. `VectorPath.fitted` scales them to the caller's
    /// box.
    ///
    /// `nonisolated(unsafe)` is needed because `CGPath` is not `Sendable`. It is safe because
    /// `parse` returns a copy that nothing changes, and every reader only measures it. The
    /// wordmark is held the same way.
    private nonisolated(unsafe) static let idle = VectorPath.parse(
        "M21 3H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2z" +
        "M1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7z" +
        "m0-4v2c4.97 0 9 4.03 9 9h2c0-6.08-4.93-11-11-11z")

    private nonisolated(unsafe) static let connected = VectorPath.parse(
        "M1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7z" +
        "M19 7H5v1.63c3.96 1.28 7.09 4.41 8.37 8.37H19V7z" +
        "M1 10v2c4.97 0 9 4.03 9 9h2c0-6.08-4.93-11-11-11z" +
        "m20-7H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2z")

    func path(in rect: CGRect) -> Path {
        Path(VectorPath.fitted(live ? Self.connected : Self.idle, in: rect))
    }
}
