import Foundation
import Testing
@testable import RPMCast

/// The wire format, checked against bytes rather than against itself.
///
/// A round trip only shows that the reader and the writer agree with each other. They would agree even if both used the
/// wrong field numbers. So the first test writes out the bytes that are expected.
@Suite("A message on the wire")
struct CastMessageTests {

    /// Field 1 is a varint of 0. Then come three length-prefixed strings. Then field 5, a varint of 0, followed by the payload.
    /// `08 00` is field 1 with wire type 0. `12` is field 2 with wire type 2, and so on up to `32` for field 6.
    @Test func theBytesAreTheBytesGoogleSpecified() {
        let message = CastMessage(source: "a", destination: "b", namespace: "n", payload: "p")

        let expected = Data([
            0x08, 0x00,             // protocol_version = CASTV2_1_0
            0x12, 0x01, 0x61,       // source_id = "a"
            0x1A, 0x01, 0x62,       // destination_id = "b"
            0x22, 0x01, 0x6E,       // namespace = "n"
            0x28, 0x00,             // payload_type = STRING
            0x32, 0x01, 0x70,       // payload_utf8 = "p"
        ])

        #expect(message.encoded == expected)
    }

    @Test func aMessageSurvivesTheTrip() throws {
        let sent = CastMessage(namespace: "urn:x-cast:com.google.cast.tp.connection",
                               payload: #"{"type":"CONNECT"}"#)

        let read = try #require(CastMessage(sent.encoded))
        #expect(read == sent)
    }

    /// A payload is JSON and can contain any character. Some characters take one byte in a string and several bytes on the wire.
    /// The length must count bytes, not characters.
    @Test func aPayloadIsCountedInBytesNotInCharacters() throws {
        let sent = CastMessage(namespace: "urn:x-cast:com.google.cast.receiver",
                               payload: #"{"name":"Keuken 🎵","level":"±3dB"}"#)

        let read = try #require(CastMessage(sent.encoded))
        #expect(read.payload == sent.payload)
    }

    /// **This keeps the music playing when Google adds a field.** Any unknown field is skipped, whatever its wire type.
    @Test func aFieldNobodyHereKnowsAboutIsSteppedOver() throws {
        var extended = Data()
        extended.append(contentsOf: [0x08, 0x00])
        extended.append(contentsOf: [0x12, 0x01, 0x61])
        extended.append(contentsOf: [0x1A, 0x01, 0x62])
        extended.append(contentsOf: [0x22, 0x01, 0x6E])
        extended.append(contentsOf: [0x28, 0x00])
        extended.append(contentsOf: [0x32, 0x01, 0x70])
        // Field 9, varint. Field 10, four fixed bytes. Field 11, three of length.
        extended.append(contentsOf: [0x48, 0xAC, 0x02])
        extended.append(contentsOf: [0x55, 0x01, 0x02, 0x03, 0x04])
        extended.append(contentsOf: [0x5A, 0x03, 0x61, 0x62, 0x63])

        let read = try #require(CastMessage(extended))
        #expect(read.namespace == "n")
        #expect(read.payload == "p")
    }

    @Test func bytesThatAreNotAMessageAreNotOne() {
        #expect(CastMessage(Data([0xFF, 0xFF, 0xFF])) == nil)
        #expect(CastMessage(Data()) == nil)
    }

    /// A message with no namespace cannot be routed, so it is not a valid message.
    @Test func aMessageWithNothingToRouteItByIsRefused() {
        #expect(CastMessage(Data([0x08, 0x00, 0x28, 0x00])) == nil)
    }

    // ── the frame ──

    @Test func aFrameSaysItsLengthInFourBigEndianBytes() throws {
        let message = CastMessage(source: "a", destination: "b", namespace: "n", payload: "p")
        let framed = message.framed

        #expect(framed.prefix(4) == Data([0, 0, 0, UInt8(message.encoded.count)]))
        #expect(try #require(CastMessage(framed.dropFirst(4))) == message)
    }

    @Test func aLengthIsNotReadUntilFourBytesHaveArrived() {
        #expect(CastMessage.length(of: Data([0, 0, 1])) == nil)
        #expect(CastMessage.length(of: Data([0, 0, 1, 0])) == 256)
        #expect(CastMessage.length(of: Data([0, 1, 0, 0])) == 65536)
    }

    /// A payload longer than 127 bytes needs a two-byte length. This is where hand-written varint code usually goes wrong.
    @Test func aLongPayloadIsLengthPrefixedCorrectly() throws {
        let long = String(repeating: "x", count: 500)
        let sent = CastMessage(namespace: "n", payload: long)

        let read = try #require(CastMessage(sent.encoded))
        #expect(read.payload.count == 500)
        #expect(CastMessage.length(of: sent.framed) == sent.encoded.count)
    }
}
