import Foundation
import RPMKit

/// How many plays this device counted in each part of the day (``DayParts``), by the genre of the
/// record played. It is the part of the desktop's listening profile that the home banner reads
/// (`ListeningProfile.GenresAt`): which kinds of music this listener plays in the morning, in the
/// afternoon, in the evening and at night (``MoodPick``).
///
/// Like the desktop's, it counts this device's own listening only: the cloud keeps one total per
/// track per device, with no time of day. A play whose record has no genre the app knows is not
/// counted, because it says nothing about which kind of music is played when.
///
/// The counts belong to the account they were played under. A play for another account starts the
/// counts over. Kept in one small file, written through a temporary name. A file that is there but
/// cannot be read is never written over (``StoreFile``).
public actor DayPartPlays {
    private struct Saved: Codable, Sendable {
        var account: String?
        /// Plays by part of the day (``DayPart/rawValue``), then by genre.
        var parts: [String: [String: Int]] = [:]
    }

    private let file: URL?
    private var held = Saved()
    private var read = false
    private var mayWrite = true

    /// - Parameter file: where the counts are kept, or nil to keep them in memory only (tests).
    public init(file: URL?) {
        self.file = file
    }

    /// The usual place: beside the play log.
    public static var defaultFile: URL {
        let folder = KeptFiles.folder.appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("day-part-plays.json")
    }

    /// Counts one play of a record filed under `genre`, counted at `at` (Unix seconds), for
    /// `userId`, in the part of the day `at` falls in on this device's clock.
    public func note(userId: String, genre: String, at: Int64) {
        guard let part = DayParts.of(Self.hourOf(at, in: .current)) else { return }
        count(userId: userId, genre: genre, part: part)
    }

    /// ``note(userId:genre:at:)`` with the part of the day already known.
    public func count(userId: String, genre: String, part: DayPart) {
        guard !genre.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        readOnce()
        guard mayWrite else { return }

        if held.account != userId {
            held = Saved(account: userId)
        }
        held.parts[part.rawValue, default: [:]][genre, default: 0] += 1
        save()
    }

    /// What `userId` plays in `part` on this device, most played first (``ranked(_:)``). Empty for
    /// another account.
    public func genresAt(userId: String, part: DayPart) -> [String] {
        readOnce()
        guard held.account == userId else { return [] }
        return Self.ranked(held.parts[part.rawValue] ?? [:])
    }

    /// The hour of `at` (Unix seconds) on the clock of `zone`.
    public static func hourOf(_ at: Int64, in zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(at)))
    }

    /// The genres most played first. The name breaks a tie, so two reads of the same counts give
    /// the same order. The desktop's `ListeningProfile` sorts its shares the same way. A genre
    /// with no plays is left out.
    public static func ranked(_ plays: [String: Int]) -> [String] {
        plays.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
    }

    // ── the file ──

    private func readOnce() {
        guard !read else { return }
        read = true
        guard let file else { return }

        let loaded = StoreFile.load(file) { try RPMJSON.decoder.decode(Saved.self, from: $0) }
        mayWrite = loaded.mayWrite
        if let saved = loaded.value { held = saved }
    }

    private func save() {
        guard let file, mayWrite else { return }

        let partial = file.appendingPathExtension("part")
        do {
            try RPMJSON.encoder.encode(held).write(to: partial, options: .atomic)
            _ = try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: partial, to: file)
        } catch {
            // Kept in memory and written with the next play.
            try? FileManager.default.removeItem(at: partial)
        }
    }
}
