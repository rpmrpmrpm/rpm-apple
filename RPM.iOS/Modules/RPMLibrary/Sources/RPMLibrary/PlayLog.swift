import Foundation
import RPMKit

/// What this phone has played, and what the listener's other devices have.
///
/// **The two are kept apart. That is the whole design.** This phone's own counts are what it
/// sends, and it must be able to say what they are at any moment. A store that had added its
/// own counts and everybody else's together could never separate them again. Every send after
/// that would either repeat somebody else's plays or lose its own. So `own` holds this phone's
/// totals, and `foreign` holds one row for each other device. A total is the sum, worked out
/// on the way out and not stored.
///
/// **What travels is a total, never a count to add on.** Sending the same row twice writes the
/// same number twice. That is what makes a lost answer, a retry and a restored backup all
/// harmless. See the Lambda's `TrackPlayStore`.
///
/// This is written in the same way as `LibraryStore` writes the library cache. It uses zlib, a
/// temporary name that is then moved into place, Application Support, and it is kept out of
/// backups. A log that cannot be read means a phone that has forgotten what it played. It does
/// not mean a phone that will not open.
public actor PlayLog {
    /// This phone's own count for one track, and how much of it the cloud has taken.
    private struct Own: Codable, Sendable {
        var plays: Int64 = 0
        var lastPlayedAt: Int64 = 0
        var sent: Int64 = 0
    }

    /// One other device's count for one track, as it was last reported.
    private struct Foreign: Codable, Sendable {
        var plays: Int64 = 0
        var lastPlayedAt: Int64 = 0
    }

    private struct Saved: Codable, Sendable {
        var own: [String: Own] = [:]
        var foreign: [String: [String: Foreign]] = [:]
        var cursor: Int64 = 0
    }

    private let path: URL?
    private var held = Saved()

    /// One sync pass's hold on the log, taken before the pass's first await.
    ///
    /// The log takes in what a pass brings back, and hands out rows to send, only while no
    /// ``forget()`` has happened since the pass began. A pass that was still running when the
    /// user signed out would otherwise write the old account's rows and cursor into the empty
    /// log that the next account starts with. It could also send the next account's plays under
    /// the old account's device id. Every read and write a pass makes takes one, so none of them
    /// can be made without it.
    public struct Pass: Sendable {
        fileprivate let era: Int
    }

    /// Moved on by ``forget()`` before it clears anything.
    private var era = 0

    /// Begins a sync pass. See ``Pass``.
    public func pass() -> Pass { Pass(era: era) }

    /// False when the file is there but could not be read this session. In that case nothing is
    /// written. If it were written, the empty log in memory would replace every play that the
    /// file held. See ``StoreFile``.
    private var mayWrite = true

    /// The newest stamp this phone has taken in. It is what the phone asks the store for next
    /// time, so a launch does not read the whole history again.
    public var cursor: Int64 { held.cursor }

    public init(at path: URL) {
        self.path = path
    }

    /// A log with no file behind it, for tests. Everything else behaves the same.
    public init(inMemory: Bool) {
        self.path = inMemory ? nil : Self.defaultPath
    }

    public init() {
        self.path = Self.defaultPath
    }

    private static var defaultPath: URL {
        let folder = KeptFiles.folder.appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("plays.json.z")
    }

    // ── counting ──

    /// Counts one play of a track on this phone.
    ///
    /// A track with no cloud id is not counted. There is nothing for the row to be keyed on. A
    /// row keyed on an empty string would be sent to the store and refused.
    public func note(rpmId: String, at lastPlayedAt: Int64) {
        guard !rpmId.isEmpty else { return }

        var mine = held.own[rpmId] ?? Own()
        mine.plays += 1
        mine.lastPlayedAt = max(mine.lastPlayedAt, lastPlayedAt)
        held.own[rpmId] = mine

        // Written now, not at the next sync pass. If it were saved only at the pass, a phone
        // with no signal would keep the whole evening in memory alone. iOS can also close a
        // backgrounded app without asking. A write of a few kilobytes is small next to losing
        // the listening that this feature is made of.
        save()
    }

    /// Everything anybody has played of this track: this phone's own count plus every other
    /// device's.
    public func plays(of rpmId: String) -> Int {
        let mine = held.own[rpmId]?.plays ?? 0
        let theirs = held.foreign[rpmId]?.values.reduce(Int64(0)) { $0 + $1.plays } ?? 0
        return Int(mine + theirs)
    }

    /// When it was last played on any of the listener's devices, or zero for never.
    public func lastPlayed(of rpmId: String) -> Int64 {
        let mine = held.own[rpmId]?.lastPlayedAt ?? 0
        let theirs = held.foreign[rpmId]?.values.map(\.lastPlayedAt).max() ?? 0
        return max(mine, theirs)
    }

    /// What anybody has played of one track: the count, and when it was last played.
    public struct Played: Sendable, Equatable {
        public let plays: Int
        public let lastPlayedAt: Int64
    }

    /// Everything that has been played, in one read.
    ///
    /// **This is what the shelf is built from.** If it were asked track by track, building the
    /// rows would take two hops into this actor for each track in the library. That happens on
    /// the launch path, and again on every return to the front. For a collection of twenty
    /// thousand songs, that is forty thousand waits, to work out a number that does not change
    /// while it is being read.
    public func everythingPlayed() -> [String: Played] {
        var totals: [String: Played] = [:]
        totals.reserveCapacity(held.own.count + held.foreign.count)

        for id in Set(held.own.keys).union(held.foreign.keys) {
            let mine = held.own[id]
            let theirs = held.foreign[id]?.values ?? [:].values

            totals[id] = Played(
                plays: Int((mine?.plays ?? 0) + theirs.reduce(Int64(0)) { $0 + $1.plays }),
                lastPlayedAt: max(mine?.lastPlayedAt ?? 0,
                                  theirs.map(\.lastPlayedAt).max() ?? 0))
        }

        return totals
    }

    // ── the cloud ──

    /// This phone's rows that hold more plays than the cloud has taken, as totals. The result is
    /// empty for a pass from before a ``forget()``.
    public func unsent(limit: Int, in pass: Pass) -> [TrackPlaysEntry] {
        guard pass.era == era else { return [] }

        return held.own
            .filter { $0.value.plays > $0.value.sent }
            .sorted { $0.key < $1.key }
            .prefix(limit)
            .map { TrackPlaysEntry(rpmId: $0.key, plays: $0.value.plays,
                                   lastPlayedAt: $0.value.lastPlayedAt) }
    }

    /// Records that the cloud has taken these rows.
    ///
    /// What is written down is the value that was SENT. It is carried on the rows that the
    /// caller was handed, not the count as it stands now. A play counted between the read and
    /// this call stays unsent, and it goes in the next pass. If the current count were written
    /// instead, that play would be lost.
    public func noteSent(_ sent: [TrackPlaysEntry], in pass: Pass) {
        guard pass.era == era else { return }

        for row in sent {
            guard var mine = held.own[row.rpmId] else { continue }
            mine.sent = row.plays
            held.own[row.rpmId] = mine
        }

        save()
    }

    /// Takes in rows from the listener's OTHER devices.
    ///
    /// - Parameter mine: This phone's own device id. Rows with this id are skipped. They are
    ///   this phone's own rows coming back from the store, already counted in `own`. Taking one
    ///   in would count it twice. These rows also do not move the cursor. The cursor says what
    ///   has been taken in. Moving it on the phone's own echo would skip another device's row
    ///   that was written in between.
    /// - Returns: How many rows changed anything.
    @discardableResult
    public func apply(_ rows: [CloudTrackPlays], mine: String, in pass: Pass) -> Int {
        guard pass.era == era else { return 0 }

        var applied = 0

        for row in rows where !row.rpmId.isEmpty {
            if row.deviceId == mine { continue }

            var forTrack = held.foreign[row.rpmId] ?? [:]
            let had = forTrack[row.deviceId]

            // A row that goes backwards is taken as it stands. A device that was reinstalled
            // reports fewer plays than before. The total is what is there now, not a high-water mark.
            if had?.plays == row.plays && (had?.lastPlayedAt ?? 0) >= row.lastPlayedAt { continue }

            forTrack[row.deviceId] = Foreign(
                plays: row.plays,
                lastPlayedAt: max(had?.lastPlayedAt ?? 0, row.lastPlayedAt))
            held.foreign[row.rpmId] = forTrack
            held.cursor = max(held.cursor, row.updatedAt)
            applied += 1
        }

        if applied > 0 { save() }

        return applied
    }

    /// Moves the cursor on by hand.
    ///
    /// **A pass calls this after every pull, not only after a pull that applied something.**
    /// The rows that a phone ignores are its own rows and the ones it already holds. Those are
    /// most of what comes back. If only ``apply(_:mine:in:)`` moved the cursor, a listener with
    /// only a phone would never move it, and would ask for their whole history on every launch.
    public func noteCursor(_ stamp: Int64, in pass: Pass) {
        guard pass.era == era, stamp > held.cursor else { return }
        held.cursor = stamp
        save()
    }

    /// Clears everything, for signing out. The next account to sign in on this phone must not
    /// see the last account's plays, and must not send its unsent plays under its own account.
    /// The file is removed even when it could not be read this session. What it holds belongs to
    /// the account that is leaving. Plays that the cloud had not taken yet are lost with it, as
    /// radio listens are.
    public func forget() {
        era += 1
        held = Saved()
        mayWrite = true

        guard let path else { return }
        try? FileManager.default.removeItem(at: path)
        try? FileManager.default.removeItem(at: path.appendingPathExtension("part"))
    }

    // ── the file ──

    /// Reads the file. A file that does not parse is moved aside, and the log starts empty. A
    /// file that could not be read is left alone, and nothing is written this session. These two
    /// cases must be kept apart. A file that could not be read is never overwritten, because the
    /// next save would replace all of its plays with an empty log.
    public func load() {
        guard let path else { return }

        let read = StoreFile.load(path) { zipped in
            let json = try (zipped as NSData).decompressed(using: .zlib) as Data
            return try RPMJSON.decoder.decode(Saved.self, from: json)
        }
        mayWrite = read.mayWrite
        if let saved = read.value { held = saved }
    }

    public func save() {
        guard let path, mayWrite else { return }

        let partial = path.appendingPathExtension("part")
        do {
            let json = try RPMJSON.encoder.encode(held)
            let zipped = try (json as NSData).compressed(using: .zlib) as Data
            try zipped.write(to: partial, options: .atomic)

            _ = try? FileManager.default.removeItem(at: path)
            try FileManager.default.moveItem(at: partial, to: path)
        } catch {
            // A log that will not write means a phone that re-sends what it already sent. The
            // store takes that as the same total again, so nothing is lost and nothing is counted twice.
            try? FileManager.default.removeItem(at: partial)
        }
    }
}
