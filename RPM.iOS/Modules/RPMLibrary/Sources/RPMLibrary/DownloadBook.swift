import Foundation
import RPMKit

/// The albums downloaded to this phone, and the files that hold them.
///
/// Two facts are kept together under one lock:
///
/// - **which albums were asked for**, with their tracks as they were when the album was
///   asked for. The list in the profile can then be drawn offline, and a removal knows
///   which files belong to the album.
/// - **which tracks have a file**, and at what rate.
///
/// Everything the screens show is derived from those two facts when it is asked for. An
/// album is on the phone when every one of its tracks has a file. It is downloading while
/// some of them do not. Nothing is stored that could disagree with them.
///
/// **One lock for the facts and the files.** A download finishing and a removal can
/// arrive in either order, from two threads. ``keep(_:from:kilobits:)`` asks "is this
/// track still wanted?" and moves the file inside the same lock that ``drop(_:)`` deletes
/// under. So whichever call runs second sees what the first one did: a finished download
/// for an album that was just removed is thrown away, and a removal after a download
/// deletes the file it finds.
///
/// The data is stored under Application Support and excluded from backup. The files are
/// copies of what is in the cloud, so iCloud does not need to hold them. The system must
/// not purge them the way it purges caches.
public final class DownloadBook: @unchecked Sendable {
    public struct Album: Codable, Sendable, Equatable {
        public let key: String
        public let album: String
        public let artist: String
        public let tracks: [CloudTrack]

        /// When the album was asked for. The list is sorted newest first.
        public let asked: Date

        public var asAlbum: CloudAlbum {
            CloudAlbum(key: key, album: album, artist: artist, tracks: tracks)
        }
    }

    public struct Copy: Codable, Sendable, Equatable {
        public let kilobits: Int
        public let bytes: Int64
    }

    private struct Manifest: Codable {
        var albums: [String: Album] = [:]
        var copies: [String: Copy] = [:]
    }

    private let lock = NSLock()
    private let root: URL
    private let tracksDir: URL
    private let manifestFile: URL
    private var held = Manifest()

    /// Which album each wanted track belongs to. Rebuilt whenever ``held`` changes.
    private var owner: [String: String] = [:]

    public init(root: URL) {
        self.root = root
        tracksDir = root.appendingPathComponent("tracks", isDirectory: true)
        manifestFile = root.appendingPathComponent("manifest.json")

        let files = FileManager.default
        try? files.createDirectory(at: tracksDir, withIntermediateDirectories: true)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = root
        try? marked.setResourceValues(values)

        lock.withLock {
            if let data = try? Data(contentsOf: manifestFile),
               let read = try? JSONDecoder().decode(Manifest.self, from: data) {
                held = read
            }
            reconcile()
        }
    }

    /// The default folder for downloads.
    public static var standard: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Downloads", isDirectory: true)
    }

    // ── reading ──

    /// The file for a track, if this phone holds one.
    public func held(_ rpmId: String) -> (file: URL, kilobits: Int)? {
        lock.withLock {
            guard let copy = held.copies[rpmId] else { return nil }
            return (file(of: rpmId), copy.kilobits)
        }
    }

    /// Every album that was asked for, newest first.
    public var albums: [Album] {
        lock.withLock { held.albums.values.sorted { $0.asked > $1.asked } }
    }

    /// How many of an album's tracks have a file, out of how many it has. Nil for an
    /// album nobody asked for.
    public func count(of key: String) -> (have: Int, of: Int)? {
        lock.withLock {
            guard let album = held.albums[key] else { return nil }
            let have = album.tracks.filter { held.copies[$0.rpmId] != nil }.count
            return (have, album.tracks.count)
        }
    }

    /// How many bytes an album's files take up on the phone.
    public func bytes(of key: String) -> Int64 {
        lock.withLock {
            guard let album = held.albums[key] else { return 0 }
            return album.tracks.reduce(0) { $0 + (held.copies[$1.rpmId]?.bytes ?? 0) }
        }
    }

    /// Every track that is wanted and has no file yet, in the order the albums were asked
    /// for and each album's own order. What the downloader works down.
    public var missing: [String] {
        lock.withLock {
            held.albums.values.sorted { $0.asked < $1.asked }
                .flatMap(\.tracks)
                .map(\.rpmId)
                .filter { held.copies[$0] == nil }
        }
    }

    /// Whether a track belongs to an album that is still wanted.
    public func isWanted(_ rpmId: String) -> Bool {
        lock.withLock { owner[rpmId] != nil }
    }

    // ── writing ──

    /// Asks for an album. Its tracks are the ones it has now. Asking again for an album
    /// that is already asked for replaces its tracks. This is how an album that gained a
    /// track on the computer gets the new track.
    public func want(_ album: CloudAlbum, at: Date = Date()) {
        lock.withLock {
            let asked = held.albums[album.key]?.asked ?? at
            held.albums[album.key] = Album(key: album.key, album: album.album,
                                           artist: album.artist, tracks: album.tracks,
                                           asked: asked)
            reconcile()
            save()
        }
    }

    /// Takes albums off the phone. Their files are deleted now. Anything still downloading
    /// for them is thrown away when it arrives, because it is not wanted any more.
    ///
    /// - Returns: the tracks that stopped being wanted, so whoever is downloading them can
    ///   stop.
    @discardableResult
    public func drop(_ keys: Set<String>) -> Set<String> {
        lock.withLock {
            var gone = Set<String>()
            for key in keys {
                guard let album = held.albums.removeValue(forKey: key) else { continue }
                gone.formUnion(album.tracks.map(\.rpmId))
            }
            reconcile()
            save()
            return gone
        }
    }

    /// Puts a finished download in place, **if its track is still wanted**. Returns
    /// whether the file was kept. The file at `from` is moved or deleted before this
    /// returns. A background session requires this of its delegate.
    @discardableResult
    public func keep(_ rpmId: String, from: URL, kilobits: Int) -> Bool {
        lock.withLock {
            let files = FileManager.default
            guard owner[rpmId] != nil else {
                try? files.removeItem(at: from)
                return false
            }

            let to = file(of: rpmId)
            try? files.removeItem(at: to)
            do { try files.moveItem(at: from, to: to) }
            catch {
                try? files.removeItem(at: from)
                return false
            }

            let bytes = ((try? files.attributesOfItem(atPath: to.path))?[.size] as? NSNumber)?
                .int64Value ?? 0
            held.copies[rpmId] = Copy(kilobits: kilobits, bytes: bytes)
            save()
            return true
        }
    }

    /// Removes everything from the phone. Used when signing out, because the files are
    /// this account's music.
    public func forgetAll() {
        lock.withLock {
            held = Manifest()
            owner = [:]
            try? FileManager.default.removeItem(at: tracksDir)
            try? FileManager.default.createDirectory(at: tracksDir,
                                                     withIntermediateDirectories: true)
            save()
        }
    }

    // ── inside the lock ──

    /// Makes the copies agree with the albums and with the disk. A copy nobody wants is
    /// deleted. A copy whose file has gone is forgotten. A file that no copy refers to is
    /// deleted. This runs on every change, so none of the three can build up.
    private func reconcile() {
        owner = [:]
        for album in held.albums.values {
            for track in album.tracks { owner[track.rpmId] = album.key }
        }

        let files = FileManager.default

        for rpmId in held.copies.keys where owner[rpmId] == nil {
            held.copies[rpmId] = nil
            try? files.removeItem(at: file(of: rpmId))
        }

        for rpmId in held.copies.keys where !files.fileExists(atPath: file(of: rpmId).path) {
            held.copies[rpmId] = nil
        }

        let named = Set(held.copies.keys.map { file(of: $0).lastPathComponent })
        let onDisk = (try? files.contentsOfDirectory(atPath: tracksDir.path)) ?? []
        for name in onDisk where !named.contains(name) {
            try? files.removeItem(at: tracksDir.appendingPathComponent(name))
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(held) else { return }
        try? data.write(to: manifestFile, options: .atomic)
    }

    /// One file per track, named by its id. The id is escaped, because it comes from the
    /// store and nothing guarantees that it has no slash.
    private func file(of rpmId: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        let name = rpmId.addingPercentEncoding(withAllowedCharacters: allowed) ?? rpmId
        return tracksDir.appendingPathComponent(name)
    }
}
