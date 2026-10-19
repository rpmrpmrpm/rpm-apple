import Foundation
import Testing
@testable import RPMRadio

/// Takes the title metadata out of a station's audio bytes.
///
/// **Chunk boundaries are the hard part.** A `URLSession` delivers data in pieces of any
/// size. A metadata block can be split at any byte, even inside its length byte or its text,
/// so the reader keeps its state between chunks. Each test feeds the same stream in several
/// chunk sizes for this reason.
@Suite("A station's bytes, with the text taken out")
struct IcyReaderTests {

    /// Builds a stream as a station sends it. Each entry in `blocks` is `every` bytes of audio,
    /// then a metadata block. A length byte of 0 means the title is unchanged.
    func stream(every: Int, blocks: [(audio: UInt8, title: String?)]) -> Data {
        var out = Data()

        for block in blocks {
            out.append(Data(repeating: block.audio, count: every))

            guard let title = block.title else {
                out.append(0)                       // No title change: the length byte is 0
                continue
            }

            var text = Array("StreamTitle='\(title)';".utf8)
            let padded = (text.count + 15) / 16 * 16
            text.append(contentsOf: [UInt8](repeating: 0, count: padded - text.count))

            out.append(UInt8(padded / 16))
            out.append(contentsOf: text)
        }

        return out
    }

    /// Feeds the stream to the reader in chunks of `size`. Returns the audio that came out and the
    /// titles that were announced.
    func read(_ data: Data, every: Int, inChunksOf size: Int) -> (audio: Data, said: [String]) {
        var reader = IcyReader(every: every)
        var audio = Data()
        var said: [String] = []

        var at = data.startIndex
        while at < data.endIndex {
            let end = min(at + size, data.endIndex)
            audio.append(reader.take(data[at..<end]) { said.append($0) })
            at = end
        }

        return (audio, said)
    }

    /// **The key test.** With any chunk size, the output is only audio, and each title is
    /// announced once.
    @Test(arguments: [1, 2, 7, 16, 100, 999, 4096, 65536])
    func theTextComesOutWhateverTheChunksAre(size: Int) {
        let every = 400
        let sent = stream(every: every, blocks: [
            (audio: 0xA1, title: "Talk Talk - Desire"),
            (audio: 0xA2, title: nil),
            (audio: 0xA3, title: "Zara Larsson - Lush Life"),
            (audio: 0xA4, title: nil),
        ])

        let (audio, said) = read(sent, every: every, inChunksOf: size)

        #expect(audio.count == every * 4, "chunks of \(size) let \(audio.count - every * 4) bytes of text through")
        #expect(said == ["Talk Talk - Desire", "Zara Larsson - Lush Life"])

        // The audio must also be the right audio, in the right order. A reader that drops one byte
        // here breaks the decoder several seconds later.
        #expect(Array(audio.prefix(every)).allSatisfy { $0 == 0xA1 })
        #expect(Array(audio.suffix(every)).allSatisfy { $0 == 0xA4 })
    }

    /// Stations often re-send the same title. A repeated title is not announced again, because
    /// the screen and the lock screen would show the track as restarting.
    @Test func thesameTitleTwiceIsAnnouncedOnce() {
        let sent = stream(every: 32, blocks: [
            (audio: 1, title: "Talk Talk - Desire"),
            (audio: 2, title: "Talk Talk - Desire"),
            (audio: 3, title: "Talk Talk - It's My Life"),
        ])

        #expect(read(sent, every: 32, inChunksOf: 9).said
                == ["Talk Talk - Desire", "Talk Talk - It's My Life"])
    }

    /// A station with no metadata passes its bytes through unchanged. The reader does not look
    /// for metadata blocks in that case.
    @Test func aStationWithNoMetadataIsLeftAlone() {
        let audio = Data(repeating: 0x5A, count: 5000)
        var reader = IcyReader(every: 0)

        #expect(reader.take(audio) { _ in } == audio)
    }

    // ── the title inside a block ──

    /// **Titles can contain apostrophes**, so the value ends at `';`, not at the first quote.
    /// "Guns N' Roses" must come through whole.
    @Test func anApostropheInATitleIsNotTheEndOfIt() {
        let block = Array("StreamTitle='Guns N' Roses - Sweet Child O' Mine';StreamUrl='';".utf8)
        #expect(IcyReader.titleIn(block) == "Guns N' Roses - Sweet Child O' Mine")
    }

    /// Some stations leave out the `';` terminator. The zero bytes that pad the block then mark
    /// the end of the title.
    @Test func aTitleWithNoTerminatorEndsAtThePadding() {
        var block = Array("StreamTitle='Talk Talk - Desire".utf8)
        block.append(contentsOf: [UInt8](repeating: 0, count: 20))

        #expect(IcyReader.titleIn(block) == "Talk Talk - Desire")
    }

    @Test func anEmptyTitleIsNoTitle() {
        #expect(IcyReader.titleIn(Array("StreamTitle='';".utf8)) == nil)
        #expect(IcyReader.titleIn(Array("StreamUrl='http://x';".utf8)) == nil)
    }

    /// Some stations do not send UTF-8. A block that is not valid UTF-8 is read as Windows-1252,
    /// so accented letters come out correctly.
    @Test func aBlockThatIsNotUtf8IsStillRead() {
        var block = Array("StreamTitle='Bj".utf8)
        block.append(0xF6)                              // ö in Windows-1252, invalid UTF-8
        block.append(contentsOf: Array("rk - Joga';".utf8))

        #expect(IcyReader.titleIn(block) == "Bj\u{F6}rk - Joga")
    }

    /// Windows-1252 uses bytes 0x80 to 0x9F for curly quotes, dashes and the euro sign. Read as
    /// Latin-1, those bytes would be invisible control characters.
    @Test func windows1252QuotesAndDashesAreRead() {
        var block = Array("StreamTitle='".utf8)
        block.append(0x93)                              // left double quotation mark
        block.append(contentsOf: Array("Hey".utf8))
        block.append(0x94)                              // right double quotation mark
        block.append(contentsOf: Array(" ".utf8))
        block.append(0x96)                              // en dash
        block.append(contentsOf: Array(" Live';".utf8))

        #expect(IcyReader.titleIn(block) == "\u{201C}Hey\u{201D} \u{2013} Live")
    }

    /// The `icy-metaint` header gives the number of audio bytes before each metadata block.
    @Test func theHeaderSaysHowOften() throws {
        let url = try #require(URL(string: "http://station.test/live"))
        let with = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                headerFields: ["icy-metaint": "16000"]))
        let without = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                   headerFields: [:]))

        #expect(IcyReader.metaInt(of: with) == 16000)
        #expect(IcyReader.metaInt(of: without) == 0)
    }
}
