import Foundation

/// Why the music stopped.
///
/// The reason is reported by the code that knows it. It is not inferred from the playback
/// position.
///
/// Comparing the position with the length in the track's tags cannot tell the cases apart. A
/// stream that died after three seconds looks the same as a three-second record. A wrong length
/// tag makes every ending look like a failure. A stream that the store refused looks like a
/// record that finished, so the queue would move on after three seconds of a song.
///
/// Everything that can end a record knows why it ended: the parser that would not take the
/// bytes, the converter that stopped, the socket that closed early, the store that answered 403.
/// Each of them reports its reason through this type.
///
/// ``StreamedPcm/finish(_:)`` has no default value. A stream cannot end without a reason, so the
/// compiler requires one at each of the seven places where a stream ends, and a new place cannot
/// be added without one.
public struct Ending: Sendable, Equatable {
    /// What happened. There is one case for each way a source can stop, and each one is reported
    /// by the code that saw it.
    public enum Why: Sendable, Equatable {
        /// The file had no more data, and all of it decoded. **This is the only normal ending**,
        /// and the only one after which the queue moves on silently.
        case theFileRanOut

        /// The connection closed before the file was complete, for example in a tunnel or a lift.
        case theBytesStopped

        /// The store answered, but the response was not a track. Status 403 means an expired
        /// signature, which is a session problem and not a fault.
        case theStoreRefused(Int)

        /// `AudioFileStream` rejected the bytes. This is not a network problem: either the data is
        /// not a sound file, or it was given out of order.
        case theBytesWouldNotParse

        /// The converter stopped part way through. The data was a valid sound file at first and
        /// then was not.
        case theDecoderStopped

        /// It was stopped on purpose: a record skipped, a queue emptied, a sign-out.
        /// **This is never a fault and never shows a message**, because whatever stopped it is
        /// already starting something else.
        case itWasPutDown
    }

    public let why: Why

    /// Whether the **record** is over.
    ///
    /// This is not the same as `why == .theFileRanOut`. The difference is a truncated download:
    /// every byte the store sent arrived and decoded, but the store stopped sending half way
    /// through. The answer comes from the file's own header (how many packets it says it holds)
    /// compared with how many frames the decoder produced from them. Both are facts about this
    /// file and not about a tag, and they agree to within a few tens of milliseconds when nothing
    /// is wrong.
    public let reachedItsEnd: Bool

    public init(why: Why, reachedItsEnd: Bool) {
        self.why = why
        self.reachedItsEnd = reachedItsEnd
    }

    /// A record that finished the way records do.
    public static let theRecordFinished = Ending(why: .theFileRanOut, reachedItsEnd: true)

    /// What to tell the user, given how much of the record they heard.
    ///
    /// The seconds are the **record's**, not this source's: a head start uses two sources for one
    /// song, and the message depends on whether the music had really started. See
    /// ``PlaybackFailure/ended(heard:)``.
    public func failure(heard seconds: Double) -> PlaybackFailure {
        switch why {
        case .theFileRanOut:
            // Everything arrived but the record is still short: the store stopped sending. The
            // message is the same as for a dropped connection, because the listener sees the same
            // thing.
            return reachedItsEnd ? .none : PlaybackFailure.ended(heard: seconds)

        case .theBytesStopped: return PlaybackFailure.ended(heard: seconds)
        case .theStoreRefused(let status): return status == 403 || status == 401 ? .signedIn : .store
        case .theBytesWouldNotParse, .theDecoderStopped: return .notPlayable
        case .itWasPutDown: return .none
        }
    }

    /// Whether opening it again could help.
    ///
    /// **A record that cannot be decoded should not be retried three times.** The second attempt
    /// is the same as the first: the same bytes arrive and the same converter rejects them, and
    /// the listener only gets nine seconds of silence instead of three. Network failures are worth
    /// retrying, because the network may recover.
    public var worthAnotherGo: Bool {
        switch why {
        case .theFileRanOut: return !reachedItsEnd
        case .theBytesStopped: return true
        case .theStoreRefused(let status): return !(status == 401 || status == 403)
        case .theBytesWouldNotParse, .theDecoderStopped, .itWasPutDown: return false
        }
    }

    /// A short description for the log. It is read after the fact, from a phone that was in a
    /// pocket when the failure happened.
    public var said: String {
        let what: String

        switch why {
        case .theFileRanOut: what = "the file ran out"
        case .theBytesStopped: what = "the bytes stopped"
        case .theStoreRefused(let status): what = "the store said \(status)"
        case .theBytesWouldNotParse: what = "the bytes would not parse"
        case .theDecoderStopped: what = "the decoder stopped"
        case .itWasPutDown: what = "it was put down"
        }

        return reachedItsEnd ? "\(what), at the end of the record" : what
    }
}
