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

    @Test func forgettingEverythingLeavesNothing() throws {
        let book = DownloadBook(root: root)
        book.want(album("a", ["t1"]))
        book.keep("t1", from: try arrived(), kilobits: 320)

        book.forgetAll()

        #expect(book.albums.isEmpty)
        #expect(book.held("t1") == nil)
        #expect(DownloadBook(root: root).albums.isEmpty)
    }
}
