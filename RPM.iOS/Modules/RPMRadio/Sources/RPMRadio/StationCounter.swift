import Foundation

/// Turns the player's readings into radio listens.
///
/// This is the phone's counterpart of the desktop app's `RadioTally`, with one difference:
/// **a long listen is handed out in parts.** The desktop writes a listen when the station changes or
/// the window closes. iOS can close a backgrounded app at any time without asking, so a listen held
/// until the station changes would be lost. This counter therefore hands out the listening so far
/// every few minutes, and when the app goes to the background. The listen continues afterwards, and
/// only its first part counts as a tuning.
///
/// **What counts is time the station was sounding.** It is read from the player's `isPlaying` four
/// times a second. It is not time tuned. A stream that never connects delivers nothing, and a station
/// that spent five minutes reconnecting must not count more than one that played for four.
///
/// **Nothing under thirty seconds is written**, the same floor as the desktop app. Turning the dial
/// through six stations is not six listens. Once a listen has passed thirty seconds, every later part
/// is written, whatever its size.
///
/// This runs on the main actor and synchronously, and it is fed from the player's tick. It uses the
/// same design as `PlayCounter`: readings must be handled in the order they were taken. What it hands
/// out is written to ``RadioListens``, where order does not matter because the parts add up.
@MainActor
public final class StationCounter {
    /// The seconds of one listen handed out in one part.
    public struct Heard: Equatable, Sendable {
        public let station: RadioStation
        public let seconds: Double

        /// Whether these are the first seconds of the listen. The count of tunings changes at this point.
        public let newTune: Bool

        /// Unix seconds.
        public let at: Int64
    }

    /// The minimum listening time before a listen is written. This matches the desktop app's
    /// `RadioListens.NoticedSeconds`.
    public static let noticedSeconds: Double = 30

    /// Listening held before it is handed out anyway. If the app crashes or is closed, at most this
    /// much is lost.
    public static let handOutEvery: Double = 300

    /// The longest gap between two readings that still counts as listening. The tick is a quarter of a
    /// second. A longer gap means the app was suspended, and nothing is heard while the app is
    /// suspended.
    private static let longestStep: Double = 5

    private let now: () -> Date

    private var station: RadioStation?
    private var heard: Double = 0
    private var handedOut: Double = 0
    private var lastReading: Date?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Takes a reading. Returns the listen that ended, or the part that was filled, if there is one.
    ///
    /// - Parameter station: what is tuned, or nil for the library or nothing.
    /// - Parameter playing: whether it is sounding right now.
    public func read(station: RadioStation?, playing: Bool) -> Heard? {
        let at = now()
        defer { lastReading = at }

        // A different station, or none: the listen in hand ends here, and the time heard since the last
        // part is handed out. This runs BEFORE the current station is replaced. In the other order the
        // listen would no longer have a station to be written against.
        if station?.uuid != self.station?.uuid {
            let finished = handOut()
            self.station = station
            heard = 0
            handedOut = 0
            return finished
        }

        guard self.station != nil, playing, let last = lastReading else { return nil }

        let step = at.timeIntervalSince(last)
        if step > 0 && step <= Self.longestStep { heard += step }

        return heard - handedOut >= Self.handOutEvery ? handOut() : nil
    }

    /// Hands out the listening heard since the last part, and keeps the listen going. This is used when
    /// the app goes to the background. The radio keeps playing, and the next reading continues the same
    /// listen instead of counting a second tuning.
    public func handOut() -> Heard? {
        guard let station, heard >= Self.noticedSeconds, heard > handedOut else { return nil }

        let part = Heard(station: station, seconds: heard - handedOut, newTune: handedOut == 0,
                         at: Int64(now().timeIntervalSince1970))
        handedOut = heard
        return part
    }
}
