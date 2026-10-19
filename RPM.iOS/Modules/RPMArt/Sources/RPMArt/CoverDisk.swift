import Foundation

/// The sleeves this phone already has.
///
/// **The directory is its own index.** One listing, made at first use, says which records have a picture
/// here and which version of it. After that, each lookup is a dictionary read. The desktop keeps a ledger
/// file beside the pictures instead. A ledger has a failure that the listing cannot have: it can claim a
/// file that is no longer there. Then a phone with no signal would draw placeholders over a disk full of covers.
///
/// An actor, so reads and writes run off the calling thread, one at a time. They are serialised on purpose.
/// When a wall asks for twenty pictures at once, twenty concurrent file reads are no faster than twenty
/// sequential ones. They would only mean twenty threads.
public actor CoverDisk {
    private let directory: URL
    private let manager = FileManager.default

    /// What is on the disk: the record's key, the version of the picture, its size, and when it was written.
    /// Built once, from the listing.
    private struct Held {
        let stamp: Int64
        let bytes: Int
        let written: Date
    }

    private var known: [String: Held] = [:]
    private var listed = false

    /// How much of the phone this may use. There are two limits, because neither one alone is enough. A
    /// library of thumbnails is three thousand small files. A library of full scans is two hundred files that
    /// together weigh a quarter of a gigabyte.
    public static let mostFiles = 3000
    public static let mostBytes = 256 * 1024 * 1024

    private let mostFiles: Int
    private let mostBytes: Int

    public init(directory: URL,
                mostFiles: Int = CoverDisk.mostFiles,
                mostBytes: Int = CoverDisk.mostBytes) {
        self.directory = directory
        self.mostFiles = mostFiles
        self.mostBytes = mostBytes
    }

    /// The usual location: the caches folder, where the system may reclaim space when the phone is full. That is
    /// acceptable. Every picture here can be fetched again, and none of it was typed by the user.
    public static func inCaches(named folder: String = "artwork") -> CoverDisk {
        let root = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return CoverDisk(directory: root.appendingPathComponent(folder, isDirectory: true))
    }

    // ── reading ──

    /// This record's picture at exactly this version, or nil.
    public func picture(albumKey: String, stamp: Int64) -> Data? {
        list()
        guard let held = known[albumKey], held.stamp == stamp else { return nil }
        return read(albumKey, held.stamp)
    }

    /// This record's picture at whatever version is held.
    ///
    /// **For a phone with no signal.** Without the index there is no version to ask for. A cover from last week
    /// is the right answer here. The alternative is a grey square.
    public func picture(albumKey: String) -> Data? {
        list()
        guard let held = known[albumKey] else { return nil }
        return read(albumKey, held.stamp)
    }

    /// Which of these records have a picture here, at any version. One listing, not one question per record.
    public func held(_ albumKeys: [String]) -> Set<String> {
        list()
        return Set(albumKeys.filter { known[$0] != nil })
    }

    // ── writing ──

    /// Keeps a picture, replacing any version of that record that was here.
    ///
    /// The picture is written beside its final name and then moved into place. Anything that reads the final
    /// name sees either nothing or the whole picture. A half-written file would be a broken sleeve on the wall.
    /// Two tiles of one record are enough to show it.
    @discardableResult
    public func hold(albumKey: String, stamp: Int64, _ data: Data) -> Bool {
        list()

        let destination = path(albumKey, stamp)
        let beside = destination.appendingPathExtension("part")

        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: beside, options: .atomic)

            if manager.fileExists(atPath: destination.path) {
                _ = try? manager.replaceItemAt(destination, withItemAt: beside)
            } else {
                try manager.moveItem(at: beside, to: destination)
            }
        } catch {
            try? manager.removeItem(at: beside)
            return false
        }

        // The old version is deleted, not kept beside the new one. A record has one cover. Keeping both would
        // store a second copy of every sleeve that has ever been corrected.
        if let old = known[albumKey], old.stamp != stamp {
            try? manager.removeItem(at: path(albumKey, old.stamp))
        }

        known[albumKey] = Held(stamp: stamp, bytes: data.count, written: Date())
        trim()
        return true
    }

    /// How much of the phone the kept sleeves use.
    ///
    /// This reads the index, not the disk. The directory was already listed once, and every size is known.
    /// Walking a few thousand files again would read the disk just to learn what is already known.
    public func bytesHeld() -> Int64 {
        list()
        return known.values.reduce(Int64(0)) { $0 + Int64($1.bytes) }
    }

    /// Forgets everything. Used on sign-out, and on sign-in as a different user. A phone that is handed on
    /// must not still hold the last person's record collection.
    public func empty() {
        try? manager.removeItem(at: directory)
        known = [:]
        listed = true
    }

    // ── the disk ──

    /// `<album key>-<version>.img`. The key is already 32 hex characters, so no record name can make a path of its own.
    private func path(_ albumKey: String, _ stamp: Int64) -> URL {
        directory.appendingPathComponent("\(albumKey)-\(stamp).img")
    }

    private func read(_ albumKey: String, _ stamp: Int64) -> Data? {
        guard let data = try? Data(contentsOf: path(albumKey, stamp)), !data.isEmpty else {
            // The listing said the file was here, and it is not. The caches were emptied from outside the app, which
            // iOS may do at any time.
            known[albumKey] = nil
            return nil
        }
        return data
    }

    /// The one listing. It runs once, on first use.
    private func list() {
        guard !listed else { return }
        listed = true

        let found = (try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        for file in found where file.pathExtension == "img" {
            let name = file.deletingPathExtension().lastPathComponent

            // `<key>-<stamp>`. The key is hex, so the last dash is the only one.
            guard let dash = name.lastIndex(of: "-"),
                  let stamp = Int64(name[name.index(after: dash)...])
            else { continue }

            let albumKey = String(name[..<dash])
            let facts = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

            let held = Held(stamp: stamp,
                            bytes: facts?.fileSize ?? 0,
                            written: facts?.contentModificationDate ?? .distantPast)

            // A record left with two versions on disk, after an eviction that only partly finished, keeps the newer
            // one. The other is removed now, so it is not carried for ever.
            if let existing = known[albumKey] {
                let (keep, drop) = held.stamp > existing.stamp ? (held, existing) : (existing, held)
                try? manager.removeItem(at: path(albumKey, drop.stamp))
                known[albumKey] = keep
            } else {
                known[albumKey] = held
            }
        }
    }

    /// Drops the oldest pictures until the disk is within both limits.
    ///
    /// Ordered by when a picture was written, not when it was last read. The difference is small. A cover is
    /// read from here once per launch and then held in memory. Ordering by last use would need a write to the
    /// file system on every read, only to keep that order.
    private func trim() {
        var weight = known.values.reduce(0) { $0 + $1.bytes }
        guard known.count > mostFiles || weight > mostBytes else { return }

        // Oldest first. Ties are broken by the key, so two pictures written in the same millisecond are evicted
        // in the same order on every run.
        let oldestFirst = known.sorted {
            $0.value.written == $1.value.written ? $0.key < $1.key
                                                 : $0.value.written < $1.value.written
        }

        for (albumKey, held) in oldestFirst {
            guard known.count > mostFiles || weight > mostBytes else { break }

            try? manager.removeItem(at: path(albumKey, held.stamp))
            known[albumKey] = nil
            weight -= held.bytes
        }
    }
}
