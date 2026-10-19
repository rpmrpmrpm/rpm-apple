import Foundation
import Testing
@testable import RPMCast

/// Which stream a request asks for.
///
/// **The rule that a track change depends on.** A receiver gets the address once, in the LOAD, and keeps fetching it. A new
/// track makes a new name. The old address must then stop being answered. Otherwise the speaker plays the new song's bytes
/// after the old song's buffer. The cut-over then arrives about half a minute after the key was pressed.
@Suite("The stream a request names")
struct CastServerNamingTests {

    private func get(_ path: String) -> String {
        "GET \(path) HTTP/1.1\r\nHost: 10.0.0.2:8080\r\nUser-Agent: CrKey\r\n\r\n"
    }

    @Test func theLiveStreamIsAnswered() {
        #expect(CastServer.asksFor("abc123", in: get("/abc123.wav")))
    }

    @Test func anOlderStreamIsNot() {
        #expect(CastServer.asksFor("abc123", in: get("/def456.wav")) == false)
    }

    /// A HEAD before a GET asks the same question. Some firmware sends one.
    @Test func aHeadForTheLiveStreamIsAnswered() {
        let head = "HEAD /abc123.wav HTTP/1.1\r\nHost: 10.0.0.2:8080\r\n\r\n"
        #expect(CastServer.asksFor("abc123", in: head))
    }

    /// **Only the request line counts.** A name in a header, such as a referer or a cookie, is not what was asked for.
    @Test func onlyTheRequestLineCounts() {
        let sneaky = "GET /def456.wav HTTP/1.1\r\nReferer: http://x/abc123.wav\r\n\r\n"
        #expect(CastServer.asksFor("abc123", in: sneaky) == false)
    }

    /// No name yet. This is the state before the first stream is named. It answers any request, as this server always did,
    /// rather than refusing everything.
    @Test func nothingNamedAnswersAnything() {
        #expect(CastServer.asksFor("", in: get("/rpm.wav")))
    }

    @Test func rubbishIsNotTheLiveStream() {
        #expect(CastServer.asksFor("abc123", in: "") == false)
    }

    /// Two names in a row are never the same.
    @Test func everyNameIsItsOwn() {
        let names = (0..<50).map { _ in CastServer.name() }
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { !$0.contains("-") && !$0.isEmpty })
    }
}
