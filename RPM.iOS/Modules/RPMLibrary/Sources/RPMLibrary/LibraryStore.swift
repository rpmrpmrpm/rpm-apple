import Foundation
import CryptoKit
import RPMKit

/// The library listing, kept on the phone between launches.
///
/// What it saves is the **listing**, the rows that `cloud/list` returns. It does not save the
/// albums built from them. The grouping is a rule that changes with the app, and a cache of
/// its output would keep drawing yesterday's rule after an update. Rows are facts. Albums are
/// an opinion about them.
///
/// The data is compressed. The JSON is a few thousand near-identical rows, and it compresses
/// about tenfold. So a megabyte is kept on the phone rather than ten, and a read is faster
/// for the same reason. The file is written to a temporary name and then moved into place.
/// So a launch that is killed mid-write does not leave a truncated file that parses as half
/// a library.
///
/// **zlib, not gzip, and the extension says so.** The desktop app writes `.json.gz` files
/// with gzip. Foundation's compressor writes a different format, and the two cannot read
/// each other's files. Nothing needs them to. This cache is read only by the app that wrote
/// it. A file called `.gz` that gzip cannot open would waste somebody's time, so the
/// extension is `.json.z`.
///
/// It lives in the app's own Application Support folder. That is inside the sandbox, invisible
/// to the Files app, and excluded from backup. It is a copy of what the cloud already holds.
/// Sending it through somebody's iCloud quota twice would be wasteful.
public struct LibraryStore: Sendable {
    private let path: URL

    /// One file per shelf. Stepping into a friend's records and back out is two reads from the
    /// disk, not two network requests. Neither file can be mistaken for the other.
    public init(shelf: CloudShelf, root: URL? = nil) {
        let folder = root ?? Self.defaultRoot
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Self.keepOutOfBackups(folder)

        path = folder.appendingPathComponent("\(Self.name(for: shelf)).json.z")
    }

    static var defaultRoot: URL {
        KeptFiles.folder.appendingPathComponent("library", isDirectory: true)
    }

    /// The file name for one collection.
    ///
    /// The user's own collection has a fixed name, so an update does not throw away the listing
    /// already on the phone. A borrowed collection is named after a HASH of the account id, not
    /// the id itself. An account id is somebody's identifier. A file name is the one place on a
    /// phone that can be read without opening anything. A hash is also the only spelling that is
    /// certainly a legal file name.
    public static func name(for shelf: CloudShelf) -> String {
        guard let owner = shelf.owner else { return "listing" }
        let digest = SHA256.hash(data: Data(owner.utf8))
        return "shelf-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The listing as it was last saved, or nil when there is none or it cannot be read.
    /// **A cache that cannot be read is a cache that is not there.** Nothing here is worth an
    /// exception in front of somebody who is opening their music.
    public func load() -> [CloudTrack]? {
        guard let gz = try? Data(contentsOf: path),
              let json = try? (gz as NSData).decompressed(using: .zlib) as Data
        else { return nil }

        return try? RPMJSON.decoder.decode([CloudTrack].self, from: json)
    }

    /// Writes the listing, replacing whatever was there.
    ///
    /// It goes through a temporary name and then an atomic move. A launch killed mid-write must
    /// not leave a truncated file that parses as half a library.
    public func save(_ tracks: [CloudTrack]) {
        let partial = path.appendingPathExtension("part")

        do {
            let json = try RPMJSON.encoder.encode(tracks)
            let gz = try (json as NSData).compressed(using: .zlib) as Data
            try gz.write(to: partial, options: .atomic)

            _ = try? FileManager.default.removeItem(at: path)
            try FileManager.default.moveItem(at: partial, to: path)
            Self.protect(path)
        } catch {
            // A cache that will not write only means a slower launch next time. Nothing else is
            // affected.
            try? FileManager.default.removeItem(at: partial)
        }
    }

    /// Deletes this one listing. This is used when a shelf's share has been taken back. A
    /// listing that nobody may read any more must not stay on the phone waiting to be drawn.
    public func delete() {
        try? FileManager.default.removeItem(at: path)
    }

    /// Deletes every saved listing, the user's own and every borrowed one. This is used
    /// when signing out, and for nothing else.
    public static func deleteAll(root: URL? = nil) {
        let folder = root ?? defaultRoot
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil) else { return }

        for file in files where file.lastPathComponent.hasSuffix(".json.z") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // ── the sandbox ──

    private static func keepOutOfBackups(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func protect(_ url: URL) {
        // Readable while the phone is locked, because a listing is read at launch, and a launch
        // can happen from a background wake.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
    }
}
