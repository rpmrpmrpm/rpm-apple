import Foundation
import Testing
import CryptoKit
@testable import RPMSharing
import RPMKit

/// The expected values come from a line-by-line port of `PeerIdentity` and `Base32` in `RPM.Core`,
/// so these tests check that this code gives the same results.
@Suite struct PeerWireTests {
    @Test func aDeviceIdIsBase32OfTheFirst16BytesOfTheKeysHash() {
        let key = Data((0..<91).map { UInt8($0) })
        #expect(PeerWire.id(for: key) == "B3998PDJ2C52W58JABA0HEAYDM")
        #expect(PeerWire.id(for: key).count == 26)
    }

    @Test func anAccountFingerprintIsBase32OfTheFirst12BytesOfTheUserIdsHash() {
        #expect(PeerWire.accountFingerprint("1245d484-d071-70ea-e9d3-e196ee969043") == "CYX35Q9479VVA3ZQEYN0")
        #expect(PeerWire.accountFingerprint("  ") == "")
        #expect(PeerWire.accountFingerprint(nil) == "")
    }

    @Test func base64UrlHasNoPaddingAndNoPlusOrSlash() {
        let bytes = Data([0xFB, 0xFF, 0x00, 0x01, 0x02])
        #expect(PeerWire.base64Url(bytes) == "-_8AAQI")
        #expect(PeerWire.fromBase64Url("-_8AAQI") == bytes)
        #expect(PeerWire.fromBase64Url("not base 64 url!!") == nil)
    }

    @Test func theSessionTextIsThePurposeTheServersIdAndTheChallenge() {
        let text = PeerWire.sessionText(serverDeviceId: "B3998PDJ2C52W58JABA0HEAYDM", challenge: "abc")
        #expect(String(decoding: text, as: UTF8.self) == "rpm-share-session\nB3998PDJ2C52W58JABA0HEAYDM\nabc")
    }

    @Test func ticksBecomeUnixSeconds() {
        // The expected value is midnight UTC on 1 January 2025, as Unix seconds.
        #expect(PeerWire.unixSeconds(ticks: 638_712_864_000_000_000) == 1_735_689_600)
        #expect(PeerWire.unixSeconds(ticks: 0) == 0)
    }

    @Test func aSignatureIsRAndSOf32BytesEachAndVerifies() async throws {
        let store = MemorySecrets()
        let me = await PeerIdentity.load(from: store)
        let text = PeerWire.sessionText(serverDeviceId: "X", challenge: "y")
        let signature = try me.sign(text)
        #expect(signature.count == 64)

        let key = try P256.Signing.PublicKey(derRepresentation: me.publicKey)
        #expect(key.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: text))
    }

    @Test func theKeyIsKeptAcrossLoads() async {
        let store = MemorySecrets()
        let first = await PeerIdentity.load(from: store)
        let second = await PeerIdentity.load(from: store)
        #expect(first.publicKey == second.publicKey)
        #expect(first.deviceId == PeerWire.id(for: first.publicKey))
    }

    @Test func aBeaconMustCarryVersion3AndAnIdItsKeyImplies() throws {
        let key = P256.Signing.PrivateKey().publicKey.derRepresentation
        let id = PeerWire.id(for: key)
        let good = ["v": "3", "k": PeerWire.base64Url(key), "id": id.lowercased(), "d": "Desk", "a": "ACC"]
        let beacon = try #require(Beacon(txt: good))
        #expect(beacon.name == "Desk")
        #expect(beacon.account == "ACC")
        #expect(beacon.publicKey == key)

        var old = good; old["v"] = "2"
        #expect(Beacon(txt: old) == nil)
        var forged = good; forged["id"] = "B3998PDJ2C52W58JABA0HEAYDM"
        #expect(Beacon(txt: forged) == nil)
        var named = good; named["d"] = nil; named["n"] = "Name"
        #expect(Beacon(txt: named)?.name == "Name")
        var nameless = good; nameless["d"] = nil
        #expect(Beacon(txt: nameless)?.name == id.lowercased())
    }
}

actor MemorySecrets: SecretStore {
    private var held: [String: Data] = [:]
    func read(_ key: String) async -> Data? { held[key] }
    func write(_ key: String, _ value: Data) async { held[key] = value }
    func delete(_ key: String) async { held[key] = nil }
}
