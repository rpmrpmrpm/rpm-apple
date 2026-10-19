import Foundation
import RPMKit
import RPMRadio

/// The last queue played on this device, kept between runs so the next launch can put it back
/// where it was left. The Android TV app keeps the same kind of record, as `LastQueue`.
///
/// **It belongs to one account.** A read for another account finds nothing, so a TV signed in by
/// a different person does not offer the previous person's music.
public struct KeptQueue: Codable, Sendable, Equatable {
    /// What was playing: either a list of tracks, with the index of the current track and the
    /// position in it in seconds, or a station.
    public enum What: Codable, Sendable, Equatable {
        case tracks([CloudTrack], at: Int, seconds: Double)
        case station(RadioStation)
    }

    /// The account the queue was played on.
    public let account: String
    public let what: What

    public init(account: String, what: What) {
        self.account = account
        self.what = what
    }
}

/// Where the last queue is kept: one small file, read at launch and written as the queue moves.
///
/// The file is written to a temporary file and then renamed, so a read sees either the old queue
/// or the new one, never part of each. This is an actor, so writes are applied in the order they
/// are called, and the last one called is the one kept.
public actor KeptQueueFile {
    private let file: URL

    public init(folder: URL) {
        file = folder.appendingPathComponent("last-queue.json")
    }

    /// The queue kept for `account`, or nil if there is none. That covers no file, a file that
    /// does not decode, a queue for another account, and a track position outside its list. A
    /// missing or unreadable file is treated the same as no queue. The only cost is that playback
    /// is not restored, because nothing else reads this file.
    public func read(for account: String) -> KeptQueue.What? {
        guard let data = try? Data(contentsOf: file),
              let kept = try? JSONDecoder().decode(KeptQueue.self, from: data),
              kept.account == account
        else { return nil }

        if case .tracks(let tracks, let at, _) = kept.what, !tracks.indices.contains(at) { return nil }
        return kept.what
    }

    /// Keeps `queue`. Passing nil removes the kept queue, for example when the queue was emptied
    /// or the account signed out.
    public func write(_ queue: KeptQueue?) {
        guard let queue else {
            try? FileManager.default.removeItem(at: file)
            return
        }

        guard let data = try? JSONEncoder().encode(queue) else { return }
        let temporary = file.appendingPathExtension("tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        } catch {
            // If the queue cannot be saved, it is not restored on the next launch.
            // Playback continues.
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}
