import Foundation
import RPMKit

/// How much each station has been heard, on this phone and on the listener's other devices.
///
/// The phone's side of `RPM.Core/Radio/RadioListens.cs`. It uses the same design as ``PlayLog`` in
/// RPMLibrary. **This phone's own totals and the other devices' totals are kept apart**, keyed by
/// device. A station's total is their sum, worked out when it is read. This phone's own totals are
/// the values it sends, so it must always be able to say what they are.
///
/// **The log names itself** the first time it is written. That name is what its rows are filed
/// under in the store. It is not the phone's play-count name. The name must not be reused. If the
/// log is lost but its old name survives somewhere, the old row comes back and is left out as
/// "mine". The phone then sends a smaller total over it. A lost log that gets a new name leaves the
/// old row in the store as another device's row, so the listening is kept.
///
/// Kept in Application Support, and written whole through a temporary file on every change. A log
/// that is there but cannot be read is not written this session, and it does not sync. See
/// ``StoreFile``.
public actor RadioListens {
    /// How many of this phone's own stations are kept. This is the same number as in the desktop
    /// app.
    public static let kept = 200

    /// How many rows from the other devices are kept. That is enough for a handful of devices.
    public static let theirsKept = kept * 4

    /// What one device has heard of one station.
    public struct Listen: Codable, Sendable, Equatable {
        public var station: RadioStation
        public var heardSeconds: Double
        public var tunes: Int

        /// Unix seconds.
        public var lastHeardAt: Int64
    }

    /// What was last sent for one of this phone's stations, as it was SENT.
    private struct Sent: Codable, Sendable, Equatable {
        var heardSeconds: Double
        var tunes: Int
    }

    private struct Saved: Codable, Sendable {
        var device: String?
        var cursor: Int64 = 0
        var own: [String: Listen] = [:]

        /// Station, then device.
        var theirs: [String: [String: Listen]] = [:]
        var sent: [String: Sent] = [:]
    }

    private let file: URL?
    private var held = Saved()

    /// False when the file is there and could not be read this session.
    private var mayWrite = true

    /// Whether the device name in ``held`` is on the disk. The log syncs only when it is.
    private var deviceWritten = false

    /// - Parameter file: where the log is kept. Nil keeps it in memory, for tests.
    public init(file: URL?) {
        self.file = file

        guard let file else {
            held.device = UUID().uuidString.lowercased()
            deviceWritten = true
            return
        }

        let read = StoreFile.load(file) { try JSONDecoder().decode(Saved.self, from: $0) }
        var saved = read.value ?? Saved()
        var written = !(saved.device ?? "").isEmpty

        // A log that has never had a name gets one now. It is written straight away, so the name is
        // on the disk before anything is sent under it.
        if read.mayWrite, !written {
            saved.device = UUID().uuidString.lowercased()
            written = Self.write(saved, to: file, mayWrite: true)
        }

        mayWrite = read.mayWrite
        held = saved
        deviceWritten = written
    }

    public static var defaultFile: URL? {
        KeptFiles.folder.appendingPathComponent("radio-listens.json")
    }

    /// This log's name in the store, or nil where it must not sync.
    public var device: String? {
        guard mayWrite, deviceWritten, let device = held.device, !device.isEmpty else { return nil }
        return device
    }

    /// The newest store stamp taken in.
    public var cursor: Int64 { held.cursor }

    /// One sync pass's hold on the log. It is taken before the pass's first await, and it holds the
    /// log's name in the store as it was when the pass began.
    ///
    /// ``forget()`` gives the log a new name. So a pass that started before it takes nothing in and
    /// is given nothing to send. Without this check, a pass in flight when the user signed out
    /// would write the old account's rows and cursor into the log that the next account starts
    /// with. Or it would send the next account's listening under the old name. Every read and write
    /// that a pass makes uses its hold.
    public struct Pass: Sendable {
        /// The name the pass sends under.
        public let device: String
    }

    /// Starts a sync pass, or returns nil where the log must not sync. See ``Pass``.
    public func pass() -> Pass? { device.map(Pass.init(device:)) }

    /// Whether a pass started under the log's current name.
    private func current(_ pass: Pass) -> Bool { pass.device == held.device }

    // ── listening ──

    /// Adds seconds of listening on this phone.
    ///
    /// The phone is given seconds, not a finished listen. A long listen is written down in parts
    /// (see ``StationCounter``). iOS can close a backgrounded app without warning. An evening of
    /// radio held in memory until the station changed would be lost with the app.
    ///
    /// - Parameter newTune: whether these are the first seconds of a listen. The count of tunings
    ///   goes up only then.
    public func note(_ station: RadioStation, seconds: Double, newTune: Bool, at: Int64) {
        guard seconds > 0, !station.uuid.isEmpty else { return }

        var mine = held.own[station.uuid]
            ?? Listen(station: station, heardSeconds: 0, tunes: 0, lastHeardAt: 0)

        // The station as it was tuned this time. A renamed or moved station keeps its hours.
        mine.station = Self.stored(station)
        mine.heardSeconds += seconds
        if newTune { mine.tunes += 1 }
        mine.lastHeardAt = max(mine.lastHeardAt, at)
        held.own[station.uuid] = mine

        trim()
        save()
    }

    /// The stations heard most, most first. Every device's listening is counted.
    public func top(_ count: Int) -> [Listen] {
        guard count > 0 else { return [] }

        return totals()
            .sorted { ($0.heardSeconds, $0.lastHeardAt) > ($1.heardSeconds, $1.lastHeardAt) }
            .prefix(count)
            .map { $0 }
    }

    // ── the cloud ──

    /// Takes in rows from the listener's other devices.
    ///
    /// Rows with this log's own name are left out. They are already counted here. Each row replaces
    /// the one with the same station and device, because that row is the device's total.
    @discardableResult
    public func apply(_ rows: [CloudStationListens], in pass: Pass) -> Int {
        guard current(pass) else { return 0 }

        let mine = pass.device
        var taken = 0

        for row in rows where !row.deviceId.isEmpty && row.deviceId != mine {
            guard let station = row.station.flatMap(RadioStation.init(listened:)) else { continue }

            let next = Listen(station: station,
                              heardSeconds: max(0, row.heardSeconds),
                              tunes: max(0, row.tunes),
                              lastHeardAt: max(0, row.lastHeardAt))

            // A row that is already held unchanged is not taken again. The listing includes the
            // cursor's second, so the newest row comes back on every pass. Counting it would write
            // the log to disk each time for nothing. The totals are compared, as the desktop app
            // does.
            if let was = held.theirs[station.uuid]?[row.deviceId],
               was.heardSeconds == next.heardSeconds, was.tunes == next.tunes,
               was.lastHeardAt == next.lastHeardAt {
                continue
            }

            held.theirs[station.uuid, default: [:]][row.deviceId] = next
            taken += 1
        }

        if taken > 0 {
            trimTheirs()
            save()
        }
        return taken
    }

    /// Moves the cursor on to the newest stamp that arrived, whether or not its rows were taken in.
    public func noteCursor(_ stamp: Int64, in pass: Pass) {
        guard current(pass), stamp > held.cursor else { return }
        held.cursor = stamp
        save()
    }

    /// This phone's stations whose totals changed since they were last sent, most recently heard
    /// first. Nothing is returned for a pass that began before a ``forget()``.
    public func unsent(limit: Int, in pass: Pass) -> [StationListensEntry] {
        guard current(pass) else { return [] }

        return held.own.values
            .filter { listen in
                guard let sent = held.sent[listen.station.uuid] else { return true }
                return sent.heardSeconds != listen.heardSeconds || sent.tunes != listen.tunes
            }
            .sorted { $0.lastHeardAt > $1.lastHeardAt }
            .prefix(max(0, limit))
            .map {
                StationListensEntry(uuid: $0.station.uuid, heardSeconds: $0.heardSeconds,
                                    tunes: $0.tunes, lastHeardAt: $0.lastHeardAt,
                                    station: CloudListenedStation(of: $0.station))
            }
    }

    /// Records these rows as agreed with the store. The values stored are the values as they were
    /// SENT. So a listen noted between ``unsent(limit:in:)`` and this call is still unsent, and
    /// goes in the next pass.
    public func noteSent(_ sent: [StationListensEntry], in pass: Pass) {
        guard current(pass) else { return }

        for row in sent {
            held.sent[row.uuid] = Sent(heardSeconds: row.heardSeconds, tunes: row.tunes)
        }
        save()
    }

    /// Gives back everything, when the user signs out. The next person to sign in on this phone
    /// must not find the last person's listening, and must not send it under their own account. The
    /// log takes a new name. So what the last account sent stays in the store as a device of its
    /// own.
    ///
    /// A file that could not be read this session is removed, not left alone. What it holds belongs
    /// to the account that is leaving. If it were left, it would be read again at the next launch.
    public func forget() {
        held = Saved()
        held.device = UUID().uuidString.lowercased()
        guard let file else { return }

        if !mayWrite {
            try? FileManager.default.removeItem(at: file)
            mayWrite = true
        }
        deviceWritten = Self.write(held, to: file, mayWrite: mayWrite)
    }

    // ── arithmetic ──

    private func totals() -> [Listen] {
        var byStation: [String: [Listen]] = [:]
        for (uuid, listen) in held.own { byStation[uuid, default: []].append(listen) }
        for (uuid, devices) in held.theirs {
            byStation[uuid, default: []].append(contentsOf: devices.values)
        }

        return byStation.values.compactMap { rows in
            // The station as it was most recently tuned on any device. Its name and logo come
            // from here.
            guard let newest = rows.max(by: { $0.lastHeardAt < $1.lastHeardAt }) else { return nil }
            return Listen(station: newest.station,
                          heardSeconds: rows.reduce(0) { $0 + $1.heardSeconds },
                          tunes: rows.reduce(0) { $0 + $1.tunes },
                          lastHeardAt: newest.lastHeardAt)
        }
    }

    private func trim() {
        guard held.own.count > Self.kept else { return }

        let keep = held.own.values
            .sorted { ($0.heardSeconds, $0.lastHeardAt) > ($1.heardSeconds, $1.lastHeardAt) }
            .prefix(Self.kept)
        held.own = Dictionary(uniqueKeysWithValues: keep.map { ($0.station.uuid, $0) })
        held.sent = held.sent.filter { held.own[$0.key] != nil }
    }

    private func trimTheirs() {
        let rows = held.theirs.flatMap { uuid, devices in devices.map { (uuid, $0.key, $0.value) } }
        guard rows.count > Self.theirsKept else { return }

        var kept: [String: [String: Listen]] = [:]
        for (uuid, device, listen) in rows
            .sorted(by: { ($0.2.heardSeconds, $0.2.lastHeardAt) > ($1.2.heardSeconds, $1.2.lastHeardAt) })
            .prefix(Self.theirsKept) {
            kept[uuid, default: [:]][device] = listen
        }
        held.theirs = kept
    }

    /// How a station is kept: the directory's answer, without the two fields that describe a list
    /// rather than a station.
    private static func stored(_ station: RadioStation) -> RadioStation {
        var station = station
        station.otherLogos = []
        station.shownName = nil
        return station
    }

    // ── the file ──

    private func save() {
        guard let file else { return }
        _ = Self.write(held, to: file, mayWrite: mayWrite)
    }

    /// - Returns: whether the log is now on the disk.
    private static func write(_ held: Saved, to file: URL, mayWrite: Bool) -> Bool {
        guard mayWrite, let data = try? JSONEncoder().encode(held) else { return false }
        do {
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            // A log that will not write means the phone sends what it already sent, again. The
            // store counts that as the same totals.
            return false
        }
    }
}

extension RadioStation {
    /// A station as another device reported it, or nil if the row names nothing playable.
    public init?(listened: CloudListenedStation) {
        guard !listened.uuid.isEmpty, !listened.name.isEmpty, !listened.streamUrl.isEmpty else {
            return nil
        }

        self.init(uuid: listened.uuid, name: listened.name, streamUrl: listened.streamUrl)
        homepage = listened.homepage
        favicon = listened.favicon
        country = listened.country
        countryCode = listened.countryCode
        language = listened.language
        tags = listened.tags
        codec = listened.codec
        bitrateKbps = listened.bitrateKbps
        isHls = listened.isHls
    }
}

extension CloudListenedStation {
    public init(of station: RadioStation) {
        self.init(uuid: station.uuid, name: station.name, streamUrl: station.streamUrl,
                  homepage: station.homepage, favicon: station.favicon, country: station.country,
                  countryCode: station.countryCode, language: station.language, tags: station.tags,
                  codec: station.codec, bitrateKbps: station.bitrateKbps, isHls: station.isHls)
    }
}
