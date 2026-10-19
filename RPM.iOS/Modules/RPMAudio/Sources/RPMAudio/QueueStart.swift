import Foundation
import RPMKit

/// What a tap that starts a list was on.
///
/// Decides what "Play now, keep queue" adds to the queue: the one song for a tap on a
/// row, the whole list for a Play or Shuffle button. Every caller passes it
/// explicitly and there is no default, because a row and a button reach the same code.
public enum Tapped: Sendable, Equatable {
    /// A row in an album, playlist, artist page or search result.
    case song

    /// A Play or Shuffle button for the whole list, or a list of one song.
    case list
}

/// A change to the queue that is ready to start. Only ``Player`` creates these, so the
/// only way to replace the queue is ``Player/replacing(with:from:tapped:)``. A queue
/// that the user has changed can only be replaced after ``QueueQuestion`` is answered.
public struct QueueStart: Sendable {
    enum What: Sendable {
        /// The list replaces the queue and plays from `from`.
        case replace([CloudTrack], from: Int)

        /// The tracks are inserted after the playing track and the one at `from` plays.
        /// The rest of the queue follows them.
        case playNow([CloudTrack], from: Int)
    }

    let what: What

    init(_ what: What) {
        self.what = what
    }

    /// The track this start plays first. Used to mark the tapped row before the player
    /// has opened it.
    public var firstTrack: CloudTrack? {
        switch what {
        case .replace(let tracks, let from), .playNow(let tracks, let from):
            return tracks.indices.contains(from) ? tracks[from] : nil
        }
    }
}

/// What replacing the queue would cost, worked out before anything changes.
public enum Replacing: Sendable {
    /// The user has not changed the songs still to come, so the list can replace the queue.
    case clear(QueueStart)

    /// The user changed the songs still to come. Ask before discarding them.
    case asks(QueueQuestion)
}

/// The question asked before a changed queue is replaced, with one start for each
/// answer. Cancel is not included because it starts nothing.
public struct QueueQuestion: Sendable {
    let replace: QueueStart
    let keep: QueueStart

    /// Discard: the list replaces the queue.
    public func discard() -> QueueStart { replace }

    /// Play now, keep queue: the tapped song, or the whole list for a button, plays
    /// after the current track, and the rest of the queue follows it.
    public func keepQueue() -> QueueStart { keep }
}
