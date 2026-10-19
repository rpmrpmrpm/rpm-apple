import Foundation

/// How many attempts one track gets before the player moves on.
///
/// Ported from `RPM.Core/Playback/Retries.cs`.
///
/// A track that **stopped** before its end is opened again. This turns a stream that dies
/// in the middle of a track into a short pause instead of a skip. Without a limit this is
/// an infinite loop: a file that is really shorter than its tag says stops at the same
/// place every time, and the album would stall on it silently forever. Skipping is better.
///
/// The count is per track and is reset as soon as a different track starts, so many short
/// interruptions across an album do not use up one budget for the whole session.
public struct Retries: Sendable {
    /// Three attempts. This is enough to survive a connection that drops and comes back,
    /// and few enough that a track that cannot play does not block the user, who would
    /// otherwise have to press stop.
    public static let most = 3

    private let mostGoes: Int
    private var track: String?
    private var used = 0

    public init(most: Int = Retries.most) { mostGoes = max(1, most) }

    /// How many attempts this track has used.
    public func used(_ rpmId: String) -> Int { track == rpmId ? used : 0 }

    /// Whether this track may be opened again. The attempt is counted against the track.
    public mutating func mayRetry(_ rpmId: String) -> Bool {
        guard !rpmId.isEmpty else { return false }

        if track != rpmId {
            track = rpmId
            used = 0
        }

        guard used < mostGoes else { return false }

        used += 1
        return true
    }

    /// Clears the count after a track played normally. Call it when a track starts without
    /// trouble, so a new failure half an hour later gets its full three attempts.
    public mutating func forget() {
        track = nil
        used = 0
    }
}
