import Foundation
import Testing
@testable import RPMCast

/// The cover, as something that a receiver fetches.
///
/// There are two ways to show a cover on a speaker. This is the one the stock receiver supports, because the stock receiver
/// does not know RPM's control channel. A cover served from the phone is the only cover it can be given.
@Suite("A cover a speaker can come and get")
struct CastCoverTests {

    private func get(_ path: String) -> String {
        "GET \(path) HTTP/1.1\r\nHost: 10.0.0.2:8080\r\nUser-Agent: CrKey\r\n\r\n"
    }

    @Test func aCoverIsAskedForByItsOwnRoute() {
        #expect(CastServer.asksForCover(get("/art/beef1234.jpg")))
        #expect(CastServer.asksForCover(get("/abc123.wav")) == false)
    }

    /// Only the request line counts. The same rule applies as for the stream name. A path in a header is not what was asked for.
    @Test func onlyTheRequestLineCounts() {
        let sneaky = "GET /abc123.wav HTTP/1.1\r\nReferer: http://x/art/beef.jpg\r\n\r\n"
        #expect(CastServer.asksForCover(sneaky) == false)
    }

    /// The name is per cover, not per track. The tracks on an album share one cover, so they share one address.
    @Test func theAddressCarriesTheNameItWasGiven() async throws {
        let server = CastServer(ring: PcmRing(seconds: 1))
        defer { Task { await server.stop() } }

        _ = try await server.start()

        let address = await server.coverAddress(named: "beef1234")
        #expect(address?.path == "/art/beef1234.jpg")
    }

    @Test func itServesWhatItWasGiven() async throws {
        let server = CastServer(ring: PcmRing(seconds: 1))
        _ = try await server.start()
        defer { Task { await server.stop() } }

        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5])
        await server.expectCover()
        await server.nowShowing(jpeg)

        let address = try #require(await server.coverAddress(named: "beef"))
        let (body, response) = try await URLSession.shared.data(from: address)

        #expect(body == jpeg)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    /// **The cross-origin header is what allows the read, not the fetch.** The receiver reads a small square of the cover to
    /// colour the background behind the record. Without this header, an image from another origin taints the canvas. The
    /// image still arrives and draws, but the read throws. Nothing in the app shows this, so it is easy to miss.
    @Test func itSaysTheCoverMayBeReadFromAnotherOrigin() async throws {
        let server = CastServer(ring: PcmRing(seconds: 1))
        _ = try await server.start()
        defer { Task { await server.stop() } }

        await server.expectCover()
        await server.nowShowing(Data([0xFF, 0xD8, 0xFF]))

        let address = try #require(await server.coverAddress(named: "beef"))
        let (_, response) = try await URLSession.shared.data(from: address)
        let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]

        #expect(headers["Access-Control-Allow-Origin"] as? String == "*")
    }

    /// A record with no cover gets a 404. Holding the connection open would leave the last record's cover on screen over another song.
    @Test func aRecordWithNoCoverIsANotFound() async throws {
        let server = CastServer(ring: PcmRing(seconds: 1))
        _ = try await server.start()
        defer { Task { await server.stop() } }

        await server.expectCover()
        await server.nowShowing(nil)

        let address = try #require(await server.coverAddress(named: "beef"))
        let (_, response) = try await URLSession.shared.data(from: address)

        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    /// **This is the reason the promise exists.** The address is sent in the LOAD, before anything has read a picture, so a
    /// receiver can request it first. If the empty field answered that request, it would say "this record has no cover" about
    /// a record that has one. The television would then draw a blank square for the rest of the record.
    @Test func aFetchThatArrivesFirstWaitsForThePicture() async throws {
        let server = CastServer(ring: PcmRing(seconds: 1))
        _ = try await server.start()
        defer { Task { await server.stop() } }

        let jpeg = Data([0xFF, 0xD8, 0xFF, 9, 9, 9])
        await server.expectCover()

        let address = try #require(await server.coverAddress(named: "beef"))

        async let answered = URLSession.shared.data(from: address)

        // Wait long enough for the request to be in and waiting. That is the state under test. Without the promise,
        // the request would already have had a 404 by now.
        try await Task.sleep(for: .milliseconds(300))
        await server.nowShowing(jpeg)

        let (body, response) = try await answered
        #expect(body == jpeg)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    /// A promise that the server will not keep. A receiver that waits for a cover that never arrives would keep its connection
    /// open forever, and the continuation it waits on would leak with it.
    @Test func stoppingReleasesAnybodyStillWaiting() async throws {
        let server = CastServer(ring: PcmRing(seconds: 1))
        _ = try await server.start()

        await server.expectCover()
        let address = try #require(await server.coverAddress(named: "beef"))

        async let answered = URLSession.shared.data(from: address)
        try await Task.sleep(for: .milliseconds(200))
        await server.stop()

        let (_, response) = try await answered
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }
}
