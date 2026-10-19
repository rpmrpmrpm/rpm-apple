import Foundation

/// The last list this machine published for a playlist, or the fact that it has
/// no record of one.
///
/// **This is an enum, not an optional list, because the two cases behave in
/// completely different ways.** When a base is known, a song that is in the base
/// but missing from a side has been removed on that side, and the removal must be
/// kept. When the base is unknown, the same two lists say nothing about removals.
/// A song missing from the local list may simply not have been uploaded yet.
///
/// Treating an unknown base as an empty list would make every song in the cloud
/// look new and every local song look added. That merges to a union, which is safe.
/// Treating an unknown base as a known empty list would make every song look
/// removed, so a playlist would empty itself on its first sync.
public enum PlaylistBase: Sendable, Equatable {
    /// This machine has no record of publishing this playlist. This happens when
    /// it was published before the app started recording what it sent. Nothing can
    /// be assumed to have been removed.
    case unknown

    /// The song ids this machine last wrote to the store, in the order it wrote
    /// them.
    case published([String])

    public var isKnown: Bool {
        if case .published = self { return true }
        return false
    }

    /// The published ids, or `nil` when the base is unknown. This is not public.
    /// Code outside the type must not read the ids directly, because that would
    /// bypass the known or unknown distinction.
    var ids: [String]? {
        if case .published(let ids) = self { return ids }
        return nil
    }

    /// Whether `now` is exactly the published list: the same songs in the same
    /// order.
    ///
    /// The check lives on this type so the ids stay hidden. A pusher uses it to
    /// decide whether to write at all. It returns `false` when the base is unknown,
    /// so a playlist with no record is always written and is never skipped.
    public func matches(_ now: [String]) -> Bool {
        guard let was = ids else { return false }
        return was == now
    }
}

/// Merges one playlist's song order when two devices have both changed it.
///
/// A playlist can be edited on a phone and on a computer, and the two edits can
/// happen at any time. Three lists are used: the cloud copy, which every device
/// can see; the local copy; and the list this machine last published, which is
/// what the two have in common. With all three, each change made on one side can
/// be told apart from each change made on the other. This is the only way to apply
/// both without one side silently undoing the other.
///
/// **Counts are used, not sets.** A playlist may hold the same song twice on
/// purpose. The second copy was put there by someone, so the arithmetic works
/// on counts rather than on membership.
///
/// **The published order is kept as the base.** When both sides reorder the same
/// songs, only one order can win. The cloud order wins, because every other device
/// already shows it. Songs that this side added are appended after it, in the order
/// this side has them. An addition has no place in an order the other side has
/// never seen.
///
/// Renames and moves between folders are not handled here. The name of a playlist
/// and its folder can only be changed on a computer. Those changes travel one way,
/// so there is nothing to merge.
public enum PlaylistMerge {
    /// The running order that both sides should end up with.
    ///
    /// - Parameters:
    ///   - ancestor: The list this machine last published.
    ///   - mine: The order this machine holds now.
    ///   - theirs: The order the store holds now.
    public static func songs(
        ancestor: PlaylistBase, mine: [String], theirs: [String]
    ) -> [String] {
        // If one side matches the published list exactly, the other side holds all
        // the changes. Its list is taken as it is. This is the usual case on every
        // pass. Answering it directly matters: the counting below would produce the
        // same songs, but in a different order, and could undo a reorder made here.
        if let published = ancestor.ids {
            if published == mine { return theirs }
            if published == theirs { return mine }
        }

        let want = targets(ancestor: ancestor, mine: mine, theirs: theirs)

        var merged: [String] = []
        merged.reserveCapacity(Swift.max(mine.count, theirs.count))
        var taken: [String: Int] = [:]

        // The cloud order is the base of the result.
        for id in theirs { take(id, want: want, taken: &taken, into: &merged) }

        // Then the songs this side still needs, in this side's order. These are the
        // songs added here that the cloud list does not have yet.
        for id in mine { take(id, want: want, taken: &taken, into: &merged) }

        return merged
    }

    /// The number of each song id the merged list should contain.
    ///
    /// For each id, the result is the published count, plus the additions, minus
    /// the removals. Additions and removals are each taken as the larger of the
    /// two sides' values, not their sum. **This is the rule that matters.** If both
    /// devices add the same song, that is one change made twice, not two changes.
    /// Summing would add the song twice. The same rule stops a song that both
    /// devices removed from being removed twice.
    ///
    /// When a change was made on one side only, the larger value is that side's
    /// value. So the result is simply to apply the change, which is the usual case.
    private static func targets(
        ancestor: PlaylistBase, mine: [String], theirs: [String]
    ) -> [String: Int] {
        // With no base, no removal can be shown, so none is applied. Reading the
        // base as an empty list gives this result from the same arithmetic. Every
        // song on either side then counts as an addition, and additions are kept.
        let was = ancestor.ids.map(count) ?? [:]
        let known = ancestor.isKnown

        let here = count(mine)
        let there = count(theirs)

        var want: [String: Int] = [:]

        for id in here.keys + there.keys + was.keys where want[id] == nil {
            let before = was[id] ?? 0
            let ours = here[id] ?? 0
            let theirsCount = there[id] ?? 0

            let added = Swift.max(ours - before, theirsCount - before)

            // Removals only count when the base is known. A song removed from one side
            // is removed. A song removed from both sides is still removed once.
            let removed = known ? Swift.max(before - ours, before - theirsCount) : 0

            want[id] = Swift.max(0, before + Swift.max(0, added) - Swift.max(0, removed))
        }

        return want
    }

    /// Adds one id to the merged list if the merge still needs another copy of it.
    private static func take(
        _ id: String, want: [String: Int], taken: inout [String: Int], into: inout [String]
    ) {
        let already = taken[id] ?? 0
        guard already < (want[id] ?? 0) else { return }

        taken[id] = already + 1
        into.append(id)
    }

    private static func count(_ ids: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for id in ids { counts[id, default: 0] += 1 }
        return counts
    }
}

private extension Dictionary.Keys {
    static func + (lhs: Self, rhs: Self) -> [Key] { Array(lhs) + Array(rhs) }
}
