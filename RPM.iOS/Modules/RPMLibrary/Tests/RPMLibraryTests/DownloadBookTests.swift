import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The book is where a finished download and a removal can meet, so both orders are tested, and
/// so is a book read back from disk.
@Suite("What is downloaded to the phone")
struct DownloadBookTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rpm-downloads-\(UUID().uuidString)", isDirectory: true)

    private func album(_ key: String, _ ids: [String]) -> CloudAlbum {
        CloudAlbum(key: key, album: key, artist: "Talk Talk",
                   tracks: ids.map { CloudTrack(rpmId: $0, title: $0, album: key) })
    }

    /// A file that has just finished downloading, stored outside the book's folder.
    private func arrived(_ bytes: Int = 1000) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrived-\(UUID().uuidString)")
        try Data(repeating: 7, count: bytes).write(to: file)
        return file
    }

    @Test func anAlbumIsOnThePhoneOnceEveryTrackHasAFile() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1", "t2"]))

        #expect(book.count(of: "a")! == (0, 2))
        #expect(book.missing == ["t1", "t2"])

        #expect(book.keep("t1", from: try arrived(), kilobits: 320))
        #expect(book.count(of: "a")! == (1, 2))
        #expect(book.held("t1")?.kilobits == 320)

        #expect(book.keep("t2", from: try arrived(), kilobits: 320))
        #expect(book.count(of: "a")! == (2, 2))
        #expect(book.missing.isEmpty)
        #expect(book.bytes(of: "a") == 2000)
    }

    /// **A download that arrives after its album was removed is discarded**, and the file the caller
    /// passed in is deleted too.
    @Test func aDownloadThatLandsAfterItsAlbumWasRemovedIsThrownAway() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1"]))
        book.drop(["a"])

        let file = try arrived()
        #expect(!book.keep("t1", from: file, kilobits: 320))
        #expect(book.held("t1") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// The other order: removing an album after its download has arrived deletes the stored files.
    @Test func removingAnAlbumDeletesItsFiles() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)
        let file = try #require(book.held("t1")?.file)

        let gone = book.drop(["a"])

        #expect(gone == ["t1"])
        #expect(book.held("t1") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(book.albums.isEmpty)
    }

    @Test func aBookReadBackFromTheDiskHoldsWhatWasWritten() throws {
        do {
            let book = DownloadBook(root: root)
            book.want(album("a", ["t1", "t2"]))
            book.keep("t1", from: try arrived(), kilobits: 256)
        }

        let again = DownloadBook(root: root)
        #expect(again.albums.map(\.key) == ["a"])
        #expect(again.albums.first?.tracks.map(\.rpmId) == ["t1", "t2"])
        #expect(again.held("t1")?.kilobits == 256)
        #expect(again.missing == ["t2"])
    }

    /// If a stored file is deleted outside the book, the track is missing again and must be fetched.
    @Test func aCopyWhoseFileHasGoneIsForgottenOnTheNextRead() throws {
        do {
            let book = DownloadBook(root: root)
            book.want(album("a", ["t1"]))
            book.keep("t1", from: try arrived(), kilobits: 320)
            try FileManager.default.removeItem(at: try #require(book.held("t1")?.file))
        }

        let again = DownloadBook(root: root)
        #expect(again.held("t1") == nil)
        #expect(again.missing == ["t1"])
    }

    /// Missing tracks are listed oldest request first. The album list is newest first.
    @Test func whatIsMissingComesInTheOrderItWasAskedFor() {
        let book = DownloadBook(root: root)
        book.want(album("b", ["b1", "b2"]), at: Date(timeIntervalSince1970: 200))
        book.want(album("a", ["a1"]), at: Date(timeIntervalSince1970: 100))

        #expect(book.missing == ["a1", "b1", "b2"])
        #expect(book.albums.map(\.key) == ["b", "a"], "the list is newest first")
    }

    // ── albums and playlists that share tracks ──

    /// **A track that an album and a playlist share keeps its file until both are removed**, and
    /// removing the first does not name it as gone, so its transfer is not stopped.
    @Test func aSharedTrackStaysUntilEverythingThatHoldsItIsRemoved() throws {
        let book = DownloadBook(root: root)
        let list = DownloadBook.playlistKey("p1")
        book.want(album("a", ["t1", "t2"]))
        book.want(album(list, ["t2", "t3"]))
        book.keep("t2", from: try arrived(), kilobits: 320)
        let file = try #require(book.held("t2")?.file)

        #expect(book.drop([list]) == ["t3"])
        #expect(book.held("t2") != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(book.count(of: "a")! == (1, 2))

        #expect(book.drop(["a"]) == ["t1", "t2"])
        #expect(book.held("t2") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// The same, the other way round: removing the album leaves the playlist's copy.
    @Test func removingTheAlbumLeavesThePlaylistItsTrack() throws {
        let book = DownloadBook(root: root)
        let list = DownloadBook.playlistKey("p1")
        book.want(album("a", ["t1"]))
        book.want(album(list, ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)

        #expect(book.drop(["a"]).isEmpty)
        #expect(book.count(of: list)! == (1, 1))
        #expect(book.isWanted("t1"))
    }

    /// A track held twice is fetched once: it is listed once in what is missing, and its file is
    /// counted once in the total.
    @Test func aSharedTrackIsFetchedAndCountedOnce() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1", "t2"]), at: Date(timeIntervalSince1970: 100))
        book.want(album(DownloadBook.playlistKey("p1"), ["t2", "t1", "t3", "t3"]),
                  at: Date(timeIntervalSince1970: 200))

        #expect(book.missing == ["t1", "t2", "t3"])

        book.keep("t1", from: try arrived(1000), kilobits: 320)
        book.keep("t2", from: try arrived(500), kilobits: 320)
        #expect(book.missing == ["t3"])
        #expect(book.totalBytes == 1500)
        #expect(book.bytes(of: "a") == 1500)
    }

    @Test func aPlaylistKeyIsNeverARecordKey() {
        let list = DownloadBook.playlistKey("p1")
        #expect(DownloadBook.isPlaylistKey(list))
        #expect(!DownloadBook.isPlaylistKey(AlbumGrouping.key(for: CloudTrack(rpmId: "t1", title: "t1", album: "a"))))
        #expect(!DownloadBook.isPlaylistKey(AlbumGrouping.key(relativePath: "playlist:x/y.flac",
                                                               albumArtist: nil, artist: nil, album: nil)))
    }

    @Test func forgettingEverythingLeavesNothing() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)

        book.forgetAll()

        #expect(book.albums.isEmpty)
        #expect(book.held("t1") == nil)
        #expect(DownloadBook(root: root).albums.isEmpty)
    }

    // ── whose music it is ──

    /// The server ended the session and the downloads were kept. The same account signing in
    /// again finds them.
    @Test func theSameAccountKeepsItsDownloads() throws {
        let book = DownloadBook(root: root)
        #expect(book.belong(to: "u1") == false)
        book.want(album("a", ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)

        #expect(DownloadBook(root: root).belong(to: "u1") == false)
        #expect(DownloadBook(root: root).held("t1") != nil)
    }

    /// Another account must not find the previous account's music, on the screen or on the disk.
    @Test func anotherAccountRemovesThePreviousAccountsDownloads() throws {
        let book = DownloadBook(root: root)
        book.belong(to: "u1")
        book.want(album("a", ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)
        let file = try #require(book.held("t1")?.file)

        let next = DownloadBook(root: root)
        #expect(next.belong(to: "u2"))

        #expect(next.albums.isEmpty)
        #expect(next.held("t1") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(DownloadBook(root: root).belong(to: "u2") == false, "the new account is remembered")
    }

    /// Downloads that no account claimed were made by the account signed in now, because a
    /// sign-out removes every download. They are kept.
    @Test func unclaimedDownloadsAreTakenByTheAccountSignedIn() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)

        #expect(book.belong(to: "u1") == false)
        #expect(book.held("t1") != nil)
    }

    /// After a sign-out nothing is claimed, so the next account starts with an empty book and
    /// is not told that something was removed.
    @Test func aSignOutLeavesTheDownloadsUnclaimed() {
        let book = DownloadBook(root: root)
        book.belong(to: "u1")
        book.forgetAll()

        #expect(DownloadBook(root: root).belong(to: "u2") == false)
    }
}
