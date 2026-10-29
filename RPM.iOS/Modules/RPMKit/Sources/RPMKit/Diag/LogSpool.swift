import Foundation

/// A copy of the app's recent log on disk, so a crash report sent at the next launch can carry the
/// log of the run that crashed. `LogTail` can only read the running process.
///
/// `rotate()` runs once at launch, synchronously, and moves the last run's copy to `previous.log`
/// before anything reads it or writes this run's copy (`CrashWatch.install` calls it first, before
/// the crash handlers exist). `flush()` overwrites `run.log` with this run's tail. The apps call it
/// when the scene goes inactive and every 60 seconds while it is active, so a crash loses at most
/// the last minute. Only a full-scope build flushes: an anonymous report never carries a log.
public actor LogSpool {
    public static let shared = LogSpool(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diag", isDirectory: true),
        launched: Date())

    /// How far back a flush reads. Reading the store costs more the longer the run; a crash report
    /// needs the last minutes, not the whole evening.
    static let window: TimeInterval = 30 * 60

    public nonisolated let directory: URL
    private let launched: Date

    init(directory: URL, launched: Date) {
        self.directory = directory
        self.launched = launched
    }

    nonisolated var current: URL { directory.appendingPathComponent("run.log") }
    nonisolated var previous: URL { directory.appendingPathComponent("previous.log") }

    /// Moves the last run's copy aside. Call once, first thing at launch.
    public nonisolated func rotate() {
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        guard files.fileExists(atPath: current.path) else { return }
        try? files.removeItem(at: previous)
        try? files.moveItem(at: current, to: previous)
    }

    /// Writes this run's tail so far over the last copy.
    public func flush() async {
        let since = max(launched, Date().addingTimeInterval(-Self.window))
        guard let tail = await LogTail.current(since: since) else { return }
        write(tail)
    }

    /// An atomic write, so a reader sees the old copy or the new one, never half of one.
    func write(_ text: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: current, options: .atomic)
    }

    /// The log of the run before this one, or nil when there is none.
    public nonisolated func previousRun() -> String? { read(previous) }

    /// This run's last copy, read at once: the exception handler has no time to wait for the actor.
    public nonisolated func thisRun() -> String? { read(current) }

    private nonisolated func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
