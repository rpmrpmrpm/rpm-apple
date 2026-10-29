import Foundation

/// Crashed runs waiting on disk to be sent, one JSON file each, named by the crash id.
///
/// `put` is synchronous because the exception handler calls it while the app is ending. A file is
/// removed when the server took the report or refused it (4xx: it would refuse it again). It is kept
/// when the phone was offline, the server failed (5xx) or anything else went wrong, and the next
/// launch tries again.
public struct CrashOutbox: Sendable {
    public static let shared = CrashOutbox(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diag/crashes", isDirectory: true))

    /// More than this many waiting files means a crash at every launch; the oldest are not kept.
    static let mostKept = 10

    let directory: URL

    init(directory: URL) { self.directory = directory }

    public func put(_ crash: CrashDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try RPMJSON.encoder.encode(crash).write(to: file(crash.crashId), options: .atomic)
        trim()
    }

    /// The waiting crashes, oldest first. A file that does not read is removed: it will never read.
    public func pending() -> [CrashDraft] {
        let names = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return names.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let crash = try? RPMJSON.decoder.decode(CrashDraft.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return crash
        }.sorted { $0.crashedAt < $1.crashedAt }
    }

    public func removeAll() {
        for crash in pending() { remove(crash.crashId) }
    }

    /// Sends every waiting crash with `send`, oldest first, and removes what the server took or
    /// refused. Stops at the first failure that is worth trying again: the rest would fail the same way.
    public func send(using send: @Sendable (CrashDraft) async throws -> Void) async {
        for crash in pending() {
            do {
                try await send(crash)
                remove(crash.crashId)
            } catch let error as RPMError {
                guard case .refused = error else { return }
                remove(crash.crashId)
            } catch {
                return
            }
        }
    }

    func remove(_ crashId: String) {
        try? FileManager.default.removeItem(at: file(crashId))
    }

    private func file(_ crashId: String) -> URL {
        directory.appendingPathComponent(crashId).appendingPathExtension("json")
    }

    private func trim() {
        let waiting = pending()
        for crash in waiting.dropLast(Self.mostKept) { remove(crash.crashId) }
    }
}

/// The answer to "Send crash reports automatically?", asked once with the desktop's own prompt.
public enum CrashConsent: String, Sendable {
    case unasked
    case send
    case dontSend

    static let key = "diag.crashConsent"

    public static func read(_ defaults: UserDefaults) -> CrashConsent {
        defaults.string(forKey: key).flatMap(CrashConsent.init(rawValue:)) ?? .unasked
    }

    public func write(_ defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.key)
    }

    /// What a launch does with `waiting` crashes.
    public enum Step: Equatable, Sendable { case nothing, ask, send }

    public static func next(_ consent: CrashConsent, waiting: Int) -> Step {
        guard waiting > 0 else { return .nothing }
        switch consent {
        case .unasked: return .ask
        case .send: return .send
        case .dontSend: return .nothing
        }
    }
}
