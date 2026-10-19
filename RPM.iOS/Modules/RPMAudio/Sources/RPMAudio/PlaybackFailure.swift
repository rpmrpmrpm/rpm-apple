import Foundation
import RPMKit

/// What went wrong, described for a user who wanted to play a song.
///
/// A message must be either **actionable** or **true and short**. One sentence for every failure
/// would say "the track is broken" when a train entered a tunnel, and would say nothing about the
/// one failure the listener can fix.
///
/// Port of `RPM.Core/Playback/PlaybackFailure.cs`. The sentences use the same string keys as the
/// Uno head, so translation is a lookup and not new work.
public enum PlaybackFailure: Sendable, Equatable {
    /// Nothing to say: the attempt was abandoned on purpose. For example a track skipped before
    /// it opened, a screen that was left, or a record tapped while another was still signing.
    /// **Never shown.**
    case none

    /// The phone is not on a network, or the host name could not be resolved. This is the one
    /// failure the listener can fix.
    case offline

    /// The network is available but the answer never came. This is different from being offline:
    /// waiting, or moving, helps.
    case timeout

    /// The session is no longer valid. Signing in again fixes it.
    case signedIn

    /// The store answered and refused the request.
    case store

    /// The request was accepted but no data ever arrived.
    case unreachable

    /// It was playing and stopped part way through. The data was arriving and then stopped. This
    /// is usually a tunnel or a similar loss of signal, not a fault.
    case dropped

    /// The decoder rejected the file. This is not a network problem, and waiting will not fix it.
    case notPlayable

    case unknown

    /// Reads an error as one of the above.
    ///
    /// **Cancellation is `.none` and a timeout is not.** This is the most important difference: a
    /// start abandoned because a second record was tapped must not show a red message, but a start
    /// that timed out must.
    public static func read(_ error: (any Error)?) -> PlaybackFailure {
        guard let error else { return .none }

        if error is CancellationError { return .none }

        if let rpm = error as? RPMError {
            switch rpm {
            case .offline: return .offline
            case .unauthorized: return .signedIn
            case .status(401), .status(403): return .signedIn
            case .status, .refused, .quotaExceeded, .notServed: return .store

            // A track start never raises these, but every case is named so that a new case must be
            // placed here deliberately and cannot fall through to a default.
            case .badAddress, .signInIncomplete, .signInTimedOut: return .store

            // The store sent a response that could not be read. It is not a network problem, and
            // the listener cannot fix it.
            case .decoding: return .store

            case .transport(let inner): return read(inner)
            }
        }

        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return .none
            case .timedOut: return .timeout

            // These all look the same to a user on a train.
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
                 .dataNotAllowed, .secureConnectionFailed:
                return .offline

            default: return .unknown
            }
        }

        return .unknown
    }

    /// How much of a record counts as having started.
    ///
    /// The length of the head clip plus a little more, in seconds. Audio up to this point can come
    /// from a file that was already on the phone before any of the record arrived, so it does not
    /// show whether the record itself was reachable.
    public static let started: Double = 4

    /// Reads a record that **stopped** rather than finished, by how far it got.
    ///
    /// A record that stopped after a couple of seconds never really started. The cause is the
    /// store or the account, and a retry is worthwhile. A record that stopped two minutes in
    /// had been arriving normally until then.
    public static func ended(heard seconds: Double) -> PlaybackFailure {
        seconds > started ? .dropped : .unreachable
    }

    /// Whether the network coming back would undo this.
    ///
    /// This is a switch that names every case, not a list of four, so that a new failure cannot
    /// silently default to "waiting will fix it". That answer would make the player retry a file
    /// that the decoder will reject again.
    public var blamesTheNetwork: Bool {
        switch self {
        case .offline, .timeout, .unreachable, .dropped: return true
        case .none, .signedIn, .store, .notPlayable, .unknown: return false
        }
    }

    /// The sentence, or nil for the failures that are not worth saying.
    ///
    /// The English text of `Rpm_Playback_*` in `scripts/strings.json`, word for word. Change both
    /// together.
    public var said: String? {
        switch self {
        case .none: return nil
        case .offline: return Loc.get("Rpm_Playback_Offline")
        case .timeout: return Loc.get("Rpm_Playback_Slow")
        case .signedIn: return Loc.get("Rpm_Playback_SignedOut")
        case .unreachable: return Loc.get("Rpm_Playback_Unreachable")
        case .dropped: return Loc.get("Rpm_Playback_Dropped")
        case .notPlayable: return Loc.get("Rpm_Playback_NotPlayable")
        case .store, .unknown: return Loc.get("Rpm_Playback_Failed")
        }
    }
}
