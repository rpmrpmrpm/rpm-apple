import Foundation
import Testing
@testable import RPMSharing
import RPMKit

@Suite struct HomeMergeTests {
    private func peer(_ id: String, _ path: String? = nil, codec: String? = "Flac Audio") -> PeerTrack {
        PeerTrack(rpmId: id, path: path ?? "A/B/\(id).flac", title: "T\(id)", codec: codec,
                  )
    }

    @Test func aTrackInTheCloudAndOnAComputerIsOneTrackTheCloudsRow() {
        let cloud = [CloudTrack(rpmId: "1", title: "Cloud title")]
        let merged = HomeMerge.merge(cloud, [HeldCatalog(computer: "PC", version: "v",
                                                         tracks: ["1": peer("1"), "2": peer("2")])])
        #expect(merged.map(\.rpmId) == ["1", "2"])
        #expect(merged[0].title == "Cloud title")
        #expect(merged[1].title == "T2")
        #expect(merged[1].tags?.extension == "flac")
    }

    @Test func aTrackOnTwoComputersIsTakenOnce() {
        let merged = HomeMerge.merge([], [HeldCatalog(computer: "A", version: "v", tracks: ["9": peer("9")]),
                                          HeldCatalog(computer: "B", version: "v", tracks: ["9": peer("9")])])
        #expect(merged.count == 1)
    }

    @Test func noCatalogsLeavesTheCloudListAsItIs() {
        let cloud = [CloudTrack(rpmId: "1")]
        #expect(HomeMerge.merge(cloud, []) == cloud)
    }

    @Test func ac3AndEac3PlayFromTheCloudAndUnknownContainersNever() {
        #expect(PeerFormats.playsHere(peer("1")))
        #expect(PeerFormats.playsHere(peer("2", "x.m4a", codec: "MPEG-4 Audio (mp4a)")))
        #expect(PeerFormats.playsHere(peer("3", "x.m4a", codec: "MPEG-4 Audio (alac)")))
        #expect(!PeerFormats.playsHere(peer("4", "x.m4a", codec: "MPEG-4 Audio (ec-3)")))
        #expect(!PeerFormats.playsHere(peer("5", "x.wma", codec: "Windows Media Audio")))
        #expect(!PeerFormats.playsHere(peer("6", "x.ape", codec: nil)))
        #expect(!PeerFormats.playsHere(peer("7", "noextension", codec: nil)))
    }
}
