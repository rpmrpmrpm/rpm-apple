import Foundation
import OSLog

/// The app's recent log, read back from the unified log.
///
/// The apps log through `os.Logger(subsystem: "com.rpm.player", ...)`. `OSLogStore` with the
/// current-process scope reads this process's own entries, so a report can carry them without any
/// call site changing. Values a call did not mark `.public` arrive as "<private>". Entries of an
/// earlier run cannot be read this way: `LogSpool` keeps a copy on disk for the crash report sent
/// at the next launch.
public enum LogTail {
    public static let subsystem = "com.rpm.player"

    /// The server's limit for `recent` (`FeedbackLimits.MaxRecent`, `CrashReportLimits.MaxRecent`).
    public static let maxCharacters = 64_000

    /// One entry, as `format` writes it.
    struct Line: Sendable {
        let date: Date
        let level: OSLogEntryLog.Level
        let category: String
        let message: String
    }

    /// This process's entries since `since`, newest last, or nil when the store cannot be opened.
    /// Reading the store takes time: call it off the main actor.
    static func entries(since: Date) -> [Line]? {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return nil }
        let start = store.position(date: since)
        let only = NSPredicate(format: "subsystem == %@", subsystem)
        guard let found = try? store.getEntries(at: start, matching: only) else { return nil }
        return found.compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return nil }
            return Line(date: log.date, level: log.level, category: log.category, message: log.composedMessage)
        }
    }

    /// The current run's tail, at most `maxCharacters`, or nil when there is nothing to send.
    public static func current(since: Date) async -> String? {
        await Task.detached(priority: .utility) {
            guard let lines = entries(since: since), !lines.isEmpty else { return nil }
            return trim(format(lines), maxCharacters: maxCharacters)
        }.value
    }

    /// One line per entry: time, level letter, category, message.
    static func format(_ lines: [Line]) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = TimeZone(identifier: "UTC")
        clock.dateFormat = "HH:mm:ss.SSS"
        return lines.map { line in
            "\(clock.string(from: line.date)) \(letter(line.level)) \(line.category): \(line.message)"
        }.joined(separator: "\n")
    }

    /// The end of `text`, at most `maxCharacters` long, starting at the beginning of a line so the
    /// first line is never cut in half. The newest lines are the ones a report needs.
    static func trim(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let tail = text.suffix(maxCharacters)
        guard let newline = tail.firstIndex(of: "\n") else { return String(tail) }
        return String(tail[tail.index(after: newline)...])
    }

    private static func letter(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "D"
        case .info: "I"
        case .notice: "N"
        case .error: "E"
        case .fault: "F"
        default: "-"
        }
    }
}
