import Foundation

/// How much of a track somebody has heard, added up across the seeks.
///
/// The engine's own counter is not enough. A seek restarts the audio from the new offset, so the
/// counter goes back to zero. A reader that keeps only the highest value would score the longest
/// unbroken stretch and not the real listening. If someone plays two minutes, drags back to the
/// chorus and plays two more minutes, they heard four minutes but would get credit for two. This
/// matters most for favourites: the records people skip around in are the ones the count should
/// find.
///
/// So each stretch is added to a total when it ends, and ``Listen`` judges that total. The
/// player's session separates one stretch from the next. The session changes on every play and
/// every stop, but not on a gapless changeover, so it is the one signal that shows the counter
/// was rewound. Watching for the value to fall would confuse a rewind with the counter of a
/// chained track starting from zero, and would give the incoming record the credit that belongs
/// to the outgoing one.
///
/// A restart is not a seek. A track played again from its beginning is a second listen, and the
/// first one is settled before the tally starts over. Otherwise a track on repeat would collect
/// one endless play from a hundred passes.
///
/// Port of `RPM.Core/Playback/ListenTally.cs`.
public struct ListenTally: Sendable {
    /// A start this close to the beginning means the record is played again, not that the user
    /// seeks within it. The limit is half a second: a play from the top arrives as exactly zero,
    /// and only a deliberate drag lands near it.
    public static let restartWithinSeconds: Double = 0.5

    /// A listen that has ended, for the caller to judge and record.
    public struct Listened: Equatable, Sendable {
        /// The track it was for. On this head that is the cloud id.
        public let track: String
        /// Everything heard of it, across all stretches.
        public let heardSeconds: Double
        /// How long the track is, as the player reported it.
        public let lengthSeconds: Double
    }

    private var track: String?
    private var session = 0
    private var banked: Double = 0
    private var stretch: Double = 0
    private var length: Double = 0

    public init() {}

    /// The track being counted, or nil when there is none.
    public var playing: String? { track }

    /// Everything heard of it so far: the finished stretches plus the current one.
    public var heardSeconds: Double { banked + stretch }

    /// How long that track is, or zero when not known.
    public var lengthSeconds: Double { length }

    /// Takes a reading of the player and returns the listen it ended, if it ended one.
    ///
    /// - Parameter track: What is playing now, or nil for nothing.
    /// - Parameter session: The player's play session. See the notes on the type.
    /// - Parameter startSeconds: Where the current stretch started. It is read only when the
    ///   session has changed, to tell a replay from a seek.
    /// - Parameter heardSeconds: Audio delivered in the current stretch.
    /// - Parameter lengthSeconds: The track's length, zero when unknown.
    @discardableResult
    public mutating func read(
        track incoming: String?, session incomingSession: Int, startSeconds: Double,
        heardSeconds: Double, lengthSeconds: Double
    ) -> Listened? {
        var finished: Listened?

        let moved = incoming != track
        let replayed = !moved && incomingSession != session
            && startSeconds <= Self.restartWithinSeconds

        if moved || replayed {
            if let was = track {
                finished = Listened(track: was, heardSeconds: self.heardSeconds,
                                    lengthSeconds: length)
            }
            track = incoming
            banked = 0
            stretch = 0
            length = 0
        } else if incomingSession != session {
            // A seek: the same listen continues, and the counter underneath is back at zero.
            banked += stretch
            stretch = 0
        }

        session = incomingSession

        guard incoming != nil else { return finished }

        // Never lower the value within a stretch. A chained track's counter starts from zero
        // again, and a reading taken slightly early, while the sink is still playing the end of
        // the outgoing track, would otherwise discard what this track has already earned.
        if heardSeconds > stretch { stretch = heardSeconds }
        if lengthSeconds > 0 { length = lengthSeconds }

        return finished
    }

    /// Ends the current listen and returns it. Use it when the player shuts down or goes to the
    /// background with a record still loaded. The tally is left empty, so the same listen cannot
    /// be counted twice.
    public mutating func settle() -> Listened? {
        guard let was = track else { return nil }

        let finished = Listened(track: was, heardSeconds: heardSeconds, lengthSeconds: length)
        track = nil
        banked = 0
        stretch = 0
        length = 0
        return finished
    }
}
