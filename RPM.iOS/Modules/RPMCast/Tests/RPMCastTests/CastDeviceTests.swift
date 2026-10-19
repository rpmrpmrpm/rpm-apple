import Testing
@testable import RPMCast

/// What makes a speaker a speaker, and what makes two of them different.
///
/// The identity rule matches `RPM.Core.Tests`. The case that matters most is this: a group and its host share an address.
/// Merging them by address hides the group, which is the only destination that can be cast to.
@Suite("A speaker, off what it advertises")
struct CastDeviceTests {

    private let kitchen = ["fn": "Kitchen", "md": "Google Home Mini", "id": "abc123"]

    @Test func aSpeakerTakesTheNameItsOwnerGaveIt() throws {
        let device = try #require(CastDevice.from(txt: kitchen, host: "192.168.1.40", port: 8009))

        #expect(device.name == "Kitchen")
        #expect(device.model == "Google Home Mini")
        #expect(device.id == "abc123")
        #expect(!device.isGroup)
    }

    @Test func aServiceWithNoAddressIsAResolveThatHasNotFinished() {
        #expect(CastDevice.from(txt: kitchen, host: nil, port: 8009) == nil)
        #expect(CastDevice.from(txt: kitchen, host: "", port: 8009) == nil)
    }

    @Test func aSpeakerThatAdvertisesNoNameIsCalledByItsAddress() throws {
        let device = try #require(
            CastDevice.from(txt: ["md": "Chromecast"], host: "192.168.1.40", port: 8009))

        #expect(device.name == "192.168.1.40")
    }

    @Test(arguments: ["Google Cast Group", "google cast group", "Cast GROUP"])
    func aGroupSaysSoInItsModel(model: String) throws {
        let device = try #require(
            CastDevice.from(txt: ["fn": "Downstairs", "md": model], host: "10.0.0.5", port: 32001))

        #expect(device.isGroup)
    }

    // ── device identity ──

    /// A group runs **on one of its member speakers**, at that member's address, on a different port.
    /// If the key is the address, the household collapses into one entry.
    @Test func aGroupAndItsHostShareAnAddressAndAreStillTwoThings() throws {
        let speaker = try #require(
            CastDevice.from(txt: ["fn": "Kitchen", "md": "Google Home Mini", "id": "spk-1"],
                            host: "192.168.1.40", port: 8009))
        let group = try #require(
            CastDevice.from(txt: ["fn": "Downstairs", "md": "Google Cast Group", "id": "grp-1"],
                            host: "192.168.1.40", port: 32001))

        #expect(speaker.host == group.host)
        #expect(speaker.id != group.id)
    }

    @Test func aDeviceThatAdvertisesNoIdIsKnownByWhereItAnswers() {
        #expect(CastDeviceIdentity.of(advertised: nil, host: "192.168.1.40", port: 8009)
                == "192.168.1.40:8009")
        #expect(CastDeviceIdentity.of(advertised: "   ", host: "192.168.1.40", port: 32001)
                == "192.168.1.40:32001")
    }

    @Test func anAdvertisedIdIsTakenAsItIsGivenAndTrimmed() {
        #expect(CastDeviceIdentity.of(advertised: "  abc123 ", host: "1.2.3.4", port: 8009)
                == "abc123")
    }

    /// The same speaker at a new address is still the same speaker. The advertised id makes this possible,
    /// which is why the id is preferred over the address.
    @Test func aSpeakerThatMovedIsStillTheSameSpeaker() {
        let before = CastDeviceIdentity.of(advertised: "abc123", host: "192.168.1.40", port: 8009)
        let after = CastDeviceIdentity.of(advertised: "abc123", host: "192.168.1.77", port: 8009)

        #expect(before == after)
    }
}
