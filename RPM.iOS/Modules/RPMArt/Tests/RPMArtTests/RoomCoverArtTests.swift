import Testing
import Foundation
import CoreGraphics
import ImageIO
import RPMDesign
@testable import RPMArt

/// The cover a cast receiver's screen shows: a JPEG that fits in one message where it can.
struct RoomCoverArtTests {
    private func picture(_ edge: Int) -> CGImage {
        let data = Pictures.jpeg(field: RGB(40, 90, 160), splash: RGB(230, 200, 40), share: 0.4, edge: edge)
        return Thumbnail.of(data, edge: edge)!
    }

    private func decodes(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    @Test func aCoverThatFitsComesBackAtTheFirstQuality() {
        let jpeg = RoomCoverArt.fitting(picture(RoomCoverArt.edge), limit: 44_000)
        let data = try! #require(jpeg)
        #expect(data.count <= 44_000)
        #expect(decodes(data))
    }

    /// Where nothing fits, the smallest image tried is still the answer. It is served, and a receiver
    /// that can reach the address draws it. Nil would mean the record has no cover.
    @Test func aCoverThatNeverFitsIsStillTheSmallestTried() {
        let image = picture(RoomCoverArt.edge)
        let data = try! #require(RoomCoverArt.fitting(image, limit: 10))
        #expect(decodes(data))
        let first = try! #require(RoomCoverArt.fitting(image, limit: .max))
        #expect(data.count < first.count)
    }
}
