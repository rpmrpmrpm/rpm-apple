import Foundation
import Testing
@testable import RPMSharing
import RPMKit

@Suite struct NasHostsTests {
    private let nasKey = Data([0x30, 0x59, 0x01, 0x02, 0x03])
    private let library = "0123456789abcdef0123456789abcdef"

    private var nasId: String { PeerWire.id(for: nasKey) }

    private func host(key: Data? = nil, library: String? = nil) -> PeerHost {
        PeerHost(deviceId: nasId, publicKey: PeerWire.base64Url(key ?? nasKey), name: "DiskStation",
                 libraryId: library ?? self.library)
    }

    private var seen: [String: FoundComputer] {
        [nasId.uppercased(): FoundComputer(deviceId: nasId, name: "Chivan", address: "192.168.1.20", port: 4000,
                                           publicKey: nasKey)]
    }

    private var libraryIds: [String: String] { [nasId.uppercased(): library] }

    private let owner = PairedComputer(deviceId: "OWNER", publicKey: "K", name: "Mac")

    @Test func hostsDecodeFromACatalogueAndAreEmptyWhenMissing() throws {
        let with = #"{"version":"v","tracks":[],"hosts":[{"deviceId":"N","publicKey":"K","name":"DS","libraryId":"L"}]}"#
        let without = #"{"version":"v","tracks":[]}"#
        #expect(try JSONDecoder().decode(PeerCatalog.self, from: Data(with.utf8)).hosts.first?.libraryId == "L")
        #expect(try JSONDecoder().decode(PeerCatalog.self, from: Data(without.utf8)).hosts.isEmpty)
    }

    @Test func beaconReadsTheRoleAndLibrary() throws {
        let txt = ["v": String(PeerWire.version), "id": nasId, "k": PeerWire.base64Url(nasKey), "r": "library", "l": library]
        let beacon = try #require(Beacon(txt: txt))
        #expect(beacon.role == "library")
        #expect(beacon.libraryId == library)
        #expect(Beacon(txt: ["v": String(PeerWire.version), "id": nasId, "k": PeerWire.base64Url(nasKey)])?.role == nil)
    }

    @Test func hostsFromAPairedComputerAreTrusted() {
        let trusted = HomeNetwork.trustedNas(vouched: ["OWNER": [host()]], paired: [owner], found: seen,
                                             libraryIds: libraryIds)
        #expect(trusted[nasId.uppercased()]?.port == 4000)
    }

    @Test func hostsFromAnUnknownSourceAreIgnored() {
        let trusted = HomeNetwork.trustedNas(vouched: ["STRANGER": [host()]], paired: [owner], found: seen,
                                             libraryIds: libraryIds)
        #expect(trusted.isEmpty)
    }

    @Test func emptyHostsWithdrawTheNas() {
        #expect(HomeNetwork.trustedNas(vouched: ["OWNER": []], paired: [owner], found: seen,
                                       libraryIds: libraryIds).isEmpty)
    }

    @Test func aNasWithAnotherKeyOrLibraryIsNotTrusted() {
        #expect(HomeNetwork.trustedNas(vouched: ["OWNER": [host(key: Data([9, 9]))]], paired: [owner], found: seen,
                                       libraryIds: libraryIds).isEmpty)
        #expect(HomeNetwork.trustedNas(vouched: ["OWNER": [host(library: "ffffffffffffffffffffffffffffffff")]],
                                       paired: [owner], found: seen, libraryIds: libraryIds).isEmpty)
    }

    @Test func aNasIsPreferredForATrackOnBoth() {
        let computer = HeldCatalog(computer: "AAA", version: "v", tracks: [:], fromNas: false)
        let nas = HeldCatalog(computer: "ZZZ", version: "v", tracks: [:], fromNas: true)
        #expect(HomeNetwork.nasFirst([computer, nas]).map(\.computer) == ["ZZZ", "AAA"])
    }

    @Test func mergeKeepsOneRowPerTrackAndTakesItFromTheNas() {
        let fromComputer = PeerTrack(rpmId: "1", path: "A/1.flac", title: "From the computer", codec: "Flac Audio")
        let fromNas = PeerTrack(rpmId: "1", path: "A/1.flac", title: "From the NAS", codec: "Flac Audio")
        let merged = HomeMerge.merge([], [
            HeldCatalog(computer: "AAA", version: "v", tracks: ["1": fromComputer], fromNas: false),
            HeldCatalog(computer: "ZZZ", version: "v", tracks: ["1": fromNas], fromNas: true),
        ])
        #expect(merged.count == 1)
        #expect(merged[0].title == "From the NAS")
    }
}
