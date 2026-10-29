import Foundation

/// A copy of the app's recent log on disk, so a crash report sent at the next launch can carry the
/// log of the run that crashed. `LogTail` can only read the running process.
///
/// `begin()` runs once at launch and moves the last run's copy to `previous.log` before this run
/// writes anything. `flush()` overwrites `run.log` with this run's tail. The apps call it when the
/// scene goes inactive and every 60 seconds while it is active, so a crash loses at most the last
/// minute. Only a full-scope build runs it: an anonymous report never carries a log.
public actor LogSpool {
    public static let shared = LogSpool(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diag", isDirectory: true),
        launched: Date())

    /// How far back a flush reads. Reading the store costs more the longer the run; a crash report
    /// needs the last minutes, not the whole evening.
    static let window: TimeInterval = 30 * 60

    private let directory: URL
    private let launched: Date

    init(directory: URL, launched: Date) {
        self.directory = directory
        self.launched = launched
    }

    var current: URL { directory.appendingPathComponent("run.log") }
    var previous: URL { directory.appendingPathComponent("previous.log") }

    /// Moves the last run's copy aside. Call once, first thing at launch.
    public func begin() {
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

    func write(_ text: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: current, options: .atomic)
    }

    /// The log of the run before this one, or nil when there is none.
    public func previousRun() -> String? {
        guard let data = try? Data(contentsOf: previous), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
