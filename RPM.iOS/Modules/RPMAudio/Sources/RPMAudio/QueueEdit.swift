import Foundation

/// The index arithmetic behind editing the queue while it is playing.
///
/// Ported from `RPM.Core/Playback/QueueEdit.cs`. Queue edits go wrong here:
/// **the playing track is held as a position**, so every removal above it shifts
/// it, removing several tracks shifts it several times, and removing the playing
/// track itself is a different outcome again. The music stops, and the next track
/// does not start in its place. None of this is visible in the player until the
/// wrong song starts.
///
/// These functions are pure and separate from ``Player``, so they can be tested
/// many times quickly without an audio engine.
public enum QueueEdit {
    /// What removing a set of positions does to the queue.
    public struct Removal: Equatable, Sendable {
        /// The positions to remove, **highest first**. Applied in this order, each
        /// removal cannot shift the ones still to come.
        public let removals: [Int]

        /// Where the playing track ends up, or nil when it was removed or when
        /// nothing was playing to begin with. The two cases are the same on
        /// purpose: in both there is no playing track afterwards.
        public let current: Int?

        /// Whether the playing track was one of them. The caller must **stop**
        /// playback and not start the track that took its place.
        public let removedCurrent: Bool
    }

    /// Plans the removal of `remove` from a queue of `count` tracks with the track
    /// at `current` playing.
    ///
    /// Out-of-range and repeated positions are dropped, not rejected. A list can pass
    /// a selection made against a queue that has since changed, and an edit like this
    /// should not fail because of that.
    public static func planRemoval(count: Int, current: Int?, remove: [Int]) -> Removal {
        let ordered = Array(Set(remove.filter { $0 >= 0 && $0 < count })).sorted(by: >)

        guard !ordered.isEmpty else {
            return Removal(removals: [], current: current, removedCurrent: false)
        }

        let removedCurrent = current.map(ordered.contains) ?? false

        // Each removed position before the playing track lowers its index by one.
        let above = current.map { at in ordered.filter { $0 < at }.count } ?? 0

        return Removal(removals: ordered,
                       current: removedCurrent ? nil : current.map { $0 - above },
                       removedCurrent: removedCurrent)
    }

    /// What dragging one track to another position does to the queue.
    public struct Move: Equatable, Sendable {
        /// Where the track was, clamped into the queue.
        public let from: Int

        /// Where it lands, clamped into the queue.
        public let to: Int

        /// Where the playing track ends up. **A reorder never stops playback.** The
        /// current song keeps playing, wherever it now sits in the order.
        public let current: Int?

        /// True when there is nothing to do: the drag ended where it started, or the
        /// queue is too short to reorder.
        public var isNothing: Bool { from == to }
    }

    /// Plans dragging the track at `from` to `to` in a queue of `count` tracks.
    ///
    /// The easy mistake is in what happens to the *other* positions. The track is
    /// taken out before it is put back, so every index after the old place drops by
    /// one first, and every index from the landing spot onwards rises by one after that.
    /// If only one of the two steps is applied, the playing mark ends up one row away
    /// from the song that is playing.
    ///
    /// Positions past either end are clamped, not rejected, for the same reason
    /// removals drop theirs: a drag can end outside the list, and the row being
    /// carried still has to land somewhere.
    public static func planMove(count: Int, current: Int?, from: Int, to: Int) -> Move {
        guard count > 1 else { return Move(from: 0, to: 0, current: current) }

        let start = min(max(from, 0), count - 1)
        let end = min(max(to, 0), count - 1)

        guard start != end else { return Move(from: start, to: end, current: current) }

        return Move(from: start, to: end, current: follow(current, from: start, to: end))
    }

    /// The part of the queue that may be given a new order: everything after the
    /// playing track.
    ///
    /// **The rule lives here and not at the call site**, because the drag and the row
    /// drawing use the same rule: the order can only change after the playing track.
    /// Tracks before it have already been played, and the playing track is never
    /// moved.
    ///
    /// When nothing is playing, the whole queue is still to come. This is the case
    /// when a queue is started shuffled.
    ///
    /// - Returns: the positions still to come, or nil when there are fewer than two of
    ///   them. One track or none cannot be put in a different order, so a button for
    ///   it should not be shown.
    public static func whatIsComing(count: Int, current: Int?) -> Range<Int>? {
        let first = min(max((current ?? -1) + 1, 0), max(count, 0))
        guard count - first >= 2 else { return nil }
        return first..<count
    }

    /// Whether the songs still to come differ from the list the queue was started with.
    ///
    /// This decides whether a tap that would replace the queue asks first. It is worked
    /// out from the queue each time, not kept as a flag set by each edit. So an edit that
    /// is later undone, or added songs that have since been played, stop counting without
    /// anything having to clear them.
    ///
    /// The upcoming songs must be the end of `started`, and the playing track must be the
    /// one that `started` has just before that end. The second check catches a removed
    /// next song: what is left after it is still an exact end of the list.
    ///
    /// It asks too often in one case: while an added song is playing, the songs after it
    /// can be the original list, but the playing track is not from the list. So this
    /// cannot tell where in the list it is, and it reports a change.
    ///
    /// - Parameters:
    ///   - queue: the queue's track ids, in order.
    ///   - current: the playing position, or nil when nothing is playing.
    ///   - started: the track ids of the list the queue was started with.
    /// - Returns: false when nothing is left to come, whatever the earlier edits were.
    public static func hasChangesAhead(queue: [String], current: Int?, started: [String]) -> Bool {
        let first = min(max((current ?? -1) + 1, 0), queue.count)
        let ahead = queue[first...]

        guard !ahead.isEmpty else { return false }
        guard ahead.count <= started.count, ahead.elementsEqual(started.suffix(ahead.count)) else {
            return true
        }

        // Where the playing track sits in `started` if nothing was changed. Minus one means
        // the whole list is still to come, which is correct only when nothing is playing.
        let before = started.count - ahead.count - 1

        guard let current, queue.indices.contains(current) else { return before != -1 }
        return before < 0 || queue[current] != started[before]
    }

    /// Where a position ends up once the track at `from` has been taken out and
    /// inserted at `to`. The moved track itself lands at `to`.
    private static func follow(_ index: Int?, from: Int, to: Int) -> Int? {
        guard let index else { return nil }
        guard index != from else { return to }

        // Taken out first: every index after the old place drops by one.
        let shifted = index > from ? index - 1 : index

        // Then inserted: every index from the landing spot onwards rises by one.
        return shifted >= to ? shifted + 1 : shifted
    }
}
