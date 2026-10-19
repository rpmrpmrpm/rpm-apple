import Foundation
import RPMKit

/// The queue as it is shown: which rows are on the screen, what each one's real
/// position is, and an identity that survives a drag.
///
/// Two lists show the queue (the panel over the player and the Now playing page), and
/// both need the same two rules. That is why this is a type and not two `ForEach`
/// bodies. **Neither rule is visible in the code that depends on it**:
///
/// - **A row's identity must not be only its position.** A queue can hold the same
///   song twice, so the position is part of the identity. But if the position were the
///   whole identity, a reorder would move no row at all: every row would keep its
///   identity and receive different contents. A `List` animating that draws two rows
///   in one place and a gap where the third was.
/// - **Only the current sitting is shown, not the whole queue.** Starting an album at
///   track ten must not show the nine tracks before it as if they had been played and
///   skipped. See ``Player/earliest``, which is where the sitting begins.
public struct QueueRow: Identifiable, Sendable, Equatable {
    /// Where a row stands in the sitting.
    public enum State: Sendable, Equatable {
        /// Before the playing track, and actually played.
        case played
        /// The playing track.
        case playing
        /// Still to come.
        case coming
    }

    /// Stable while the entry is in the queue, which a reorder needs.
    ///
    /// It is the track's id plus **which copy of it this is**, counted over the whole
    /// queue. A reorder changes the order of the copies, not the set of copies, so each
    /// row keeps its identity as it moves. If two copies of the same song swap places,
    /// they swap identities, which makes no visible difference: they are the same song.
    public let id: String

    /// Where this row is in the player's own queue. **Every callback takes this**, never
    /// the row's place on the screen, because the two differ as soon as any earlier
    /// part of the queue is hidden.
    public let at: Int

    public let track: CloudTrack
    public let state: State
}

/// Which part of a list is on the screen and what may be dragged where.
///
/// A stored playlist and the queue are drawn as the same rows by the same page, and
/// they differ in exactly these two facts. They are passed in as a value, not as a
/// boolean at the call site: `whole` is an explicit choice, never a default.
public struct QueueLook: Sendable, Equatable {
    /// The first position on the screen.
    public let from: Int

    /// The position of the playing track, or nil for a list that is not the queue.
    /// **The playing track fixes the past**: nothing may be dragged to a position
    /// before it.
    public let playing: Int?

    /// A stored playlist: all of it is shown, and the whole order can be changed.
    public static let whole = QueueLook(from: 0, playing: nil)

    /// The queue, as the current sitting has it.
    public static func sitting(from: Int, playing: Int?) -> QueueLook {
        QueueLook(from: from, playing: playing)
    }

    private init(from: Int, playing: Int?) {
        self.from = from
        self.playing = playing
    }
}

public enum QueueRows {
    /// The rows to draw.
    ///
    /// Out-of-range values are clamped, not rejected: `from` and `playing` are read from
    /// a player that a queue edit can change between one frame and the next, and a list
    /// should not crash because of that.
    public static func of(_ queue: [CloudTrack], _ look: QueueLook) -> [QueueRow] {
        var seen: [String: Int] = [:]
        var rows: [QueueRow] = []
        let first = min(max(look.from, 0), queue.count)

        for (at, track) in queue.enumerated() {
            // Counted over the whole queue, including the entries before the first shown
            // row: a copy's identity must not change when the sitting starts earlier.
            let copy = seen[track.rpmId, default: 0]
            seen[track.rpmId] = copy + 1

            guard at >= first else { continue }

            let state: QueueRow.State =
                at == look.playing ? .playing
                : look.playing.map({ at < $0 }) ?? false ? .played
                : .coming

            rows.append(QueueRow(id: "\(track.rpmId)#\(copy)", at: at,
                                 track: track, state: state))
        }

        return rows
    }

    /// Where a drag inside the shown rows lands in the queue itself.
    ///
    /// `SwiftUI` passes positions on the screen: an index set of the rows lifted, and
    /// the row they were dropped **before**. ``Player/move(from:to:)`` takes positions
    /// in the queue, and the landing position is counted after the moved row has been
    /// taken out. Both translations are here, with their tests, because a mistake in
    /// either puts the song one row away from where the drag ended, with no error.
    ///
    /// - Returns: nil when there is nothing to do, including a drag that ends where it
    ///   began.
    public static func drop(_ rows: [QueueRow], _ look: QueueLook,
                            from: IndexSet, to: Int, count: Int) -> (from: Int, to: Int)? {
        // One row at a time: this list has no multiple selection. If a drag did carry
        // several rows, only the first one moves.
        guard let lifted = from.first, rows.indices.contains(lifted) else { return nil }

        let source = rows[lifted].at

        // Dropped after the last row means the end of the queue, which is one past the
        // last position, not the last position itself.
        let landing = to < rows.count ? rows[to].at : count

        // Out before in: the moved row is taken out first, so a landing position after
        // it is one lower by the time the row is inserted.
        var destination = landing > source ? landing - 1 : landing

        // **A drag never lands in the past.** Rows before the playing track have already
        // been played, so a song dropped there would never play. The lowest allowed
        // position is the one after the playing track, or the first shown row when
        // nothing is playing.
        destination = max(destination, look.playing.map { $0 + 1 } ?? look.from)
        destination = min(destination, max(count - 1, 0))

        return destination == source ? nil : (from: source, to: destination)
    }
}
