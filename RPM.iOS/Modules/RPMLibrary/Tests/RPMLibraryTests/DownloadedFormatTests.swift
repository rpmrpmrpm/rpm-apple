import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// A downloaded original is checked from its own bytes, because the catalogue's codec text can be
/// missing. An E-AC-3 file in an `.m4a` does not decode on this device and is not kept.
@MainActor
@Suite("A downloaded original this device cannot decode", .serialized)
struct DownloadedFormatTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("rpm-downloads-\(UUID().uuidString)", isDirectory: true)

    /// A copy of the fixture outside the book, as a finished download is. The book moves it.
    private func dolby() throws -> URL {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/tone-eac3",
                                                     withExtension: "m4a"))
        let arrived = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrived-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixture, to: arrived)
        return arrived
    }

    private func notAudio() throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("arrived-\(UUID().uuidString)")
        try Data(repeating: 7, count: 1000).write(to: file)
        return file
    }

    @Test func dolbyInAnMpeg4FileIsFoundFromItsBytes() throws {
        #expect(DownloadedFormat.isNotDecodedHere(try dolby()))
    }

    /// A file that cannot be opened as audio is not judged: the answer is no.
    @Test func aFileThatIsNotAudioIsNotJudged() throws {
        #expect(!DownloadedFormat.isNotDecodedHere(try notAudio()))
    }

    @Test func onlyMpeg4FilesAreOpened() {
        #expect(DownloadedFormat.mayHoldDolby(CloudTrack(rpmId: "a", relativePath: "x/a.m4a")))
        #expect(DownloadedFormat.mayHoldDolby(CloudTrack(rpmId: "a", relativePath: "x/a.MP4")))
        #expect(!DownloadedFormat.mayHoldDolby(CloudTrack(rpmId: "a", relativePath: "x/a.flac")))
        #expect(!DownloadedFormat.mayHoldDolby(CloudTrack(rpmId: "a", relativePath: "x/a.mp3")))
    }

    /// A discarded track is wanted still, so it is missing again and is downloaded again.
    @Test func aDiscardedTrackIsMissingAgain() throws {
        let book = DownloadBook(root: root)
        book.want(CloudAlbum(key: "a", album: "a", artist: "Talk Talk",
                             tracks: [CloudTrack(rpmId: "t1", title: "t1", album: "a")]))
        #expect(book.keep("t1", from: try notAudio(), kilobits: AudioLadder.original))
        let file = try #require(book.held("t1")?.file)

        book.discard("t1")

        #expect(book.held("t1") == nil)
        #expect(book.missing == ["t1"])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// An original kept before the check is thrown away when the downloads begin, and noted, so
    /// the next pass asks for its AAC copy. A FLAC original is not touched.
    @Test func aKeptDolbyOriginalIsDroppedAndItsCopyIsAskedFor() async throws {
        let book = DownloadBook(root: root)
        book.want(CloudAlbum(key: "a", album: "a", artist: "Talk Talk", tracks: [
            CloudTrack(rpmId: "dolby", relativePath: "x/01 Song.m4a", title: "dolby", album: "a"),
            CloudTrack(rpmId: "flac", relativePath: "x/02 Song.flac", title: "flac", album: "a"),
        ]))
        #expect(book.keep("dolby", from: try dolby(), kilobits: AudioLadder.original))
        #expect(book.keep("flac", from: try notAudio(), kilobits: AudioLadder.original))

        let found = FoundUndecodable()
        let downloads = AlbumDownloads(
            book: book, reach: NetworkReach(),
            sign: { _, rate in (URL(string: "https://transcoder.invalid/live")!, rate.kilobits, .live) },
            make: { _, _ in },
            rate: { AudioLadder.original },
            found: found)

        await downloads.dropOriginalsThatDoNotDecode()

        #expect(book.held("dolby") == nil)
        #expect(book.held("flac") != nil)
        #expect(found.contains("dolby"))

        let dolby = CloudTrack(rpmId: "dolby", relativePath: "x/01 Song.m4a")
        #expect(AudioLadder.asked(AudioLadder.original, for: dolby, found: found).kilobits == 320)
    }
}
