import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import RPMKit
import RPMLibrary

/// A record's cover as a JPEG, for the screen in the room where a speaker plays (a cast receiver).
///
/// **The same bytes do two jobs.** They are served over HTTP, where size does not matter. They are also the
/// answer to a receiver that cannot fetch that address. There, a cover larger than the CASTV2 frame limit does
/// not fail with an error. It resets the socket (see `CastCover`). So the cover is encoded at falling qualities
/// until one fits under `limit`. If none fits, the smallest is used. It is still served, and a receiver that can
/// reach the address can draw it. The result is nil only when the record has no cover.
///
/// The method reduces quality, not size, and does not resample. A 640-pixel sleeve at quality 0.4 still looks
/// like the record on a television that draws it at half that size.
public enum RoomCoverArt {
    /// How wide the cover is asked for: comfortably more than a television draws it at.
    public static let edge = 640

    /// The qualities tried, in order.
    static let qualities: [Double] = [0.82, 0.6, 0.4]

    /// - Parameter limit: the most bytes a message may carry (`CastCover.limit`). There is no default. The limit
    ///   belongs to the receiver protocol, and this module does not know it.
    public static func jpeg(of track: CloudTrack, from store: ArtworkStore, on shelves: TrackShelves,
                            fitting limit: Int) async -> Data? {
        // The album is built from the track, rather than found in the wall. Only the key matters to the store. A
        // record played from a playlist that reaches past this account's own listing is not in the wall, so it
        // could not be found there.
        let album = CloudAlbum(key: AlbumGrouping.key(for: track), album: track.album ?? "",
                               artist: track.artist ?? "", tracks: [track])
        guard let art = await store.cover(for: album, on: shelves.shelf(ofAlbum: album), edge: edge)
        else { return nil }
        return fitting(art.image, limit: limit)
    }

    /// The first encoding that fits under `limit`, or the smallest one tried.
    static func fitting(_ image: CGImage, limit: Int) -> Data? {
        var smallest: Data?
        for quality in qualities {
            guard let jpeg = encoded(image, quality: quality) else { continue }
            if jpeg.count <= limit { return jpeg }
            smallest = jpeg
        }
        return smallest
    }

    private static func encoded(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
