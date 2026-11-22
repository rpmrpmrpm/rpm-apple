import Foundation
import RPMKit

/// The listens this device has not sent to the store yet.
///
/// **One row per listen, kept until the store has taken it.** Every listen worth writing down (a play
/// or a skip, see `Listen` in RPMAudio) goes to the store's listening log (`cloud/listens`), which cuts
/// the lists that read it: On repeat, Rediscover, Late night, First listens, and the hourly lean of
/// Your mix. This device does not cut those lists, so it keeps nothing it has sent.
///
/// **Each listen gets its id here, when it is noted.** The store keys on it, so a batch sent again
/// after a lost answer is stored once.
///
/// Written like ``PlayLog``: zlib, a temporary name that is then moved into place, Application
/// Support, kept out of backups, and a file that cannot be read is never overwritten.
public actor ListenLog {
    private struct Saved: Codable, Sendable {
        var unsent: [CloudListen] = []
    }

    /// The most listens kept. A phone that never reaches the store drops the oldest past this, so the
    /// file stays small. About a year of heavy listening.
    public static let ceiling = 20_000

    private let path: URL?
    private let keepAtMost: Int
    private var held = Saved()
    private var mayWrite = true

    /// One sync pass's hold on the log, taken before the pass's first await. See ``PlayLog/Pass``:
    /// a pass that was running when the user signed out must not send or mark anything after it.
    public struct Pass: Sendable {
        fileprivate let era: Int
    }

    private var era = 0

    public func pass() -> Pass { Pass(era: era) }

    public init(at path: URL) {
        self.path = path
        self.keepAtMost = Self.ceiling
    }

    /// A log with no file behind it, for tests.
    public init(inMemory: Bool, keepAtMost: Int = ListenLog.ceiling) {
        self.path = inMemory ? nil : Self.defaultPath
        self.keepAtMost = keepAtMost
    }

    public init() {
        self.path = Self.defaultPath
        self.keepAtMost = Self.ceiling
    }

    private static var defaultPath: URL {
        let folder = KeptFiles.folder.appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("listens.json.z")
    }

    /// Notes one finished listen.
    ///
    /// A track with no cloud id is not kept: the store has nothing to join the listen to.
    public func note(rpmId: String, at: Int64, heardSeconds: Double, lengthSeconds: Double,
                     counted: Bool, localHour: Int, localDayOfWeek: Int) {
        guard !rpmId.isEmpty else { return }

        held.unsent.append(CloudListen(
            listenId: UUID().uuidString.lowercased(), rpmId: rpmId, at: at,
            heardSeconds: heardSeconds, lengthSeconds: lengthSeconds, counted: counted,
            localHour: localHour, localDayOfWeek: localDayOfWeek))
        if held.unsent.count > keepAtMost {
            held.unsent.removeFirst(held.unsent.count - keepAtMost)
        }

        // Written now, for the reason PlayLog.note gives: iOS may close a backgrounded app without
        // asking, and a phone with no signal would otherwise hold the evening in memory alone.
        save()
    }

    /// The oldest listens the store has not taken, at most `limit`. Empty for a pass from before a
    /// ``forget()``.
    public func unsent(limit: Int, in pass: Pass) -> [CloudListen] {
        guard pass.era == era else { return [] }
        return Array(held.unsent.prefix(max(0, limit)))
    }

    /// Records that the store has taken these listens. Listens noted while they were on their way
    /// stay, because only the ids that were sent are removed.
    public func noteSent(_ sent: [CloudListen], in pass: Pass) {
        guard pass.era == era, !sent.isEmpty else { return }
        let ids = Set(sent.map(\.listenId))
        held.unsent.removeAll { ids.contains($0.listenId) }
        save()
    }

    /// Clears everything, for signing out. Listens the store had not taken are lost with the account
    /// that made them, as unsent plays are.
    public func forget() {
        era += 1
        held = Saved()
        mayWrite = true

        guard let path else { return }
        try? FileManager.default.removeItem(at: path)
        try? FileManager.default.removeItem(at: path.appendingPathExtension("part"))
    }

    /// Reads the file. See ``PlayLog/load()`` for why a file that could not be read is left alone.
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
            // The listens stay in memory and are written with the next one.
            try? FileManager.default.removeItem(at: partial)
        }
    }
}

/// One sync pass for the listening log: sends what this device has not sent, in batches, until it
/// is all sent or the store does not answer.
///
/// Nothing comes back. This device does not cut the lists that read the log, so other devices'
/// listens are of no use here.
public enum ListensSync {
    /// Listens per request, the store's own limit.
    public static let perRequest = 500

    /// Requests per pass. A phone that was away for a long time catches up over several passes.
    public static let requestsPerPass = 10

    public static func run(log: ListenLog, client: RPMCloudClient, mine: String) async {
        // Taken before the first await. See ListenLog.Pass.
        let pass = await log.pass()

        for _ in 0..<requestsPerPass {
            let due = await log.unsent(limit: perRequest, in: pass)
            guard !due.isEmpty else { return }

            do {
                _ = try await client.sendListens(deviceId: mine, listens: due)
                await log.noteSent(due, in: pass)
            } catch {
                // Kept, and sent again on the next pass. The ids make a second send harmless.
                return
            }
        }
    }
}
