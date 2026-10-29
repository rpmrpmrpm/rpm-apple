import Foundation
import RPMKit

/// The playlists of one shelf as this device knows them: the store's rows, the computer's cut,
/// and the writes this device has started.
///
/// **Reads and writes end in any order.** The app reads the playlists when it comes to the
/// foreground, when a collection opens, and when somebody presses Try again. Two of those can be
/// in flight at once, and a write can start and end between a read's request and its answer. So
/// a read's answer is not simply put on screen. It is merged into what this device already
/// knows, row by row, and the newer knowledge wins whichever answer arrives last:
///
/// - A row that the read and this device both hold: the one with the newer store stamp. The
///   store gives every write of a row a new, larger stamp.
/// - A row that this device holds and the read does not: kept when this device learned about it
///   after the read started (from a later read, or from a write that ended after it started).
///   Otherwise the store no longer has it, and it goes.
/// - The cut: kept when the read failed. A read that answered "no cut" removes it only when it
///   started after the cut was learned. A cut with an older stamp does not replace a newer one.
///
/// **A read or a write lands only through its ticket.** ``startRead()`` and ``startWrite()``
/// hand one out, and ``land(_:rows:cut:)`` and ``end(_:wrote:)`` take it back. A ticket carries
/// the value it came from. A collection switch or a sign-out makes a new value, and a ticket from
/// the old one does not land on it, even when both are the user's own shelf.
///
/// The playlists on screen are worked out from this value and a track listing by
/// ``sets(against:readings:)``. Nothing is stored in resolved form, so a new listing is resolved
/// again without another read.
public struct HeldPlaylists: Sendable {
    /// Whose playlists these are.
    public let shelf: CloudShelf

    /// Which value a ticket came from.
    private let era = UUID()

    /// Counts reads started and writes ended. It orders what this device learned, so that a
    /// read can tell whether a row it does not mention was learned after it started.
    private var clock = 0

    /// A stored row, and the ``clock`` value at which this device learned this version of it.
    private struct Known: Sendable {
        var row: CloudPlaylist
        var learned: Int
    }

    private var rows: [String: Known] = [:]

    private var cut: CloudMoodLists?
    private var cutLearned = 0

    /// The running orders of the reorders in flight, by playlist id. Each one is shown over the
    /// stored row until its write ends. The serial says which write set it, so the end of an
    /// earlier write on the same playlist does not remove a later one.
    private var writing: [String: (serial: Int, order: [String])] = [:]
    private var serial = 0

    /// Whether a read has answered.
    public private(set) var answered = false

    public init(shelf: CloudShelf) { self.shelf = shelf }

    // ── reading ──

    /// A read that has been started. See ``land(_:rows:cut:)``.
    public struct ReadTicket: Sendable {
        fileprivate let era: UUID
        fileprivate let started: Int
    }

    /// What a read learned about the cut.
    public enum CutAnswer: Sendable {
        /// The computer's last cut.
        case cut(CloudMoodLists)
        /// The store holds no cut for this shelf.
        case none
        /// The request failed. This says nothing about the cut, so what is held stays.
        case failed
    }

    /// Takes a ticket before the read's request is sent.
    public mutating func startRead() -> ReadTicket {
        clock += 1
        return ReadTicket(era: era, started: clock)
    }

    /// Whether a ticket was handed out by this value: for a read that failed, before it says so
    /// on a screen that may now show another shelf.
    public func holds(_ ticket: ReadTicket) -> Bool { ticket.era == era }

    /// Merges a read's answer. See the rules on the type.
    ///
    /// - Returns: false when the ticket came from another value. Nothing is changed then.
    public mutating func land(_ ticket: ReadTicket, rows read: [CloudPlaylist],
                              cut answer: CutAnswer) -> Bool {
        guard ticket.era == era else { return false }
        answered = true

        var merged: [String: Known] = [:]

        for row in read {
            let held = rows[row.playlistId]

            if let held, held.row.updatedAt > row.updatedAt {
                merged[row.playlistId] = held
            } else {
                merged[row.playlistId] = Known(
                    row: row, learned: max(ticket.started, held?.learned ?? 0))
            }
        }

        for (id, held) in rows where merged[id] == nil && held.learned > ticket.started {
            merged[id] = held
        }

        rows = merged

        switch answer {
        case .cut(let sent):
            if (cut?.computedAt ?? .min) <= sent.computedAt {
                cut = sent
                cutLearned = max(ticket.started, cutLearned)
            }
        case .none:
            if cutLearned < ticket.started { cut = nil }
        case .failed:
            break
        }

        return true
    }

    // ── writing ──

    /// A write that has been started. See ``end(_:wrote:)``.
    public struct WriteTicket: Sendable {
        fileprivate let era: UUID
        fileprivate let shown: (id: String, serial: Int)?
    }

    /// Takes a ticket before a write that shows nothing until it ends: a new playlist, or an add.
    public func startWrite() -> WriteTicket {
        WriteTicket(era: era, shown: nil)
    }

    /// Takes a ticket before a reorder, and shows `order` for the playlist until the write ends.
    public mutating func startWrite(showing order: [String], of id: String) -> WriteTicket {
        serial += 1
        writing[id] = (serial, order)
        return WriteTicket(era: era, shown: (id, serial))
    }

    /// Ends a write. The order it showed is removed. The row it wrote is kept, unless this device
    /// already knows a newer version of that row.
    ///
    /// A write that failed passes nil, and the playlist shows the stored row again, as the latest
    /// read or write left it.
    ///
    /// **A write lands only on the own shelf.** The phone writes only to the account's own
    /// playlists, so a row that ends while a borrowed shelf is open is not that shelf's.
    ///
    /// - Returns: false when the ticket came from another value. Nothing is changed then.
    @discardableResult
    public mutating func end(_ ticket: WriteTicket, wrote row: CloudPlaylist?) -> Bool {
        guard ticket.era == era else { return false }

        if let shown = ticket.shown, writing[shown.id]?.serial == shown.serial {
            writing[shown.id] = nil
        }

        guard let row, shelf.isOwn else { return true }

        clock += 1
        if let held = rows[row.playlistId], held.row.updatedAt > row.updatedAt { return true }
        rows[row.playlistId] = Known(row: row, learned: clock)

        return true
    }

    // ── what is shown ──

    /// The computer's last cut, or nil when there is none.
    public var moodLists: CloudMoodLists? { cut }

    /// The playlists resolved against a listing: the stored ones, then the generated ones.
    ///
    /// - Parameters:
    ///   - tracks: the listing of ``shelf``. A borrowed shelf's lists name that owner's tracks.
    ///   - readings: how many times refresh has been pressed on each generated list. See
    ///     ``GeneratedLists/sets(_:against:shelf:readings:)``.
    public func sets(against tracks: [CloudTrack], readings: [String: Int]) -> [PlaylistSet] {
        // In id order before the sort by name, so two lists with the same name keep their
        // places from one redraw to the next.
        let stored = rows.values.map(\.row)
            .sorted { $0.playlistId < $1.playlistId }
            .map { row in
                guard let shown = writing[row.playlistId] else { return row }
                return CloudPlaylist(playlistId: row.playlistId, name: row.name,
                                     trackIds: shown.order, folder: row.folderChain,
                                     updatedAt: row.updatedAt)
            }

        return PlaylistSet.resolve(stored, against: tracks, shelf: shelf)
            + (cut.map {
                GeneratedLists.sets($0, against: tracks, shelf: shelf, readings: readings)
            } ?? [])
    }
}
