import Foundation
import RPMKit
import RPMLibrary

/// Where the music comes from.
///
/// A protocol so the player can be built and tested without a network, and so it
/// depends on one question instead of the whole cloud client.
public protocol StreamSource: Sendable {
    /// A signed address for one track, the bitrate it is actually served at, and whether
    /// it is a stored object or an encode in progress.
    ///
    /// The second and third values cannot be derived from the requested rate: a free
    /// account is capped, a rendition that does not exist yet is encoded while it is
    /// downloaded, and only the store knows which of these happened.
    func stream(
        _ shelf: CloudShelf, rpmId: String, kilobits: Int
    ) async throws -> (url: URL, kilobits: Int, kind: StreamKind)

}

extension RPMCloudClient: StreamSource {}

/// Which shelf a track is on. `TrackShelves` answers this. The protocol lets the player
/// ask without being given the whole library.
public protocol ShelfSource: Sendable {
    func shelf(of rpmId: String?) -> CloudShelf
}

/// Whether the owner of the shelf marked the track's record as classical. Called on the
/// main actor, when a track is given to the engine.
public typealias ClassicalRecord = @MainActor (CloudTrack) -> Bool

/// A track this phone holds a whole copy of, and the bitrate it was downloaded at.
public struct PhoneCopy: Sendable, Equatable {
    public let file: URL
    public let kilobits: Int

    public init(file: URL, kilobits: Int) {
        self.file = file
        self.kilobits = kilobits
    }
}

/// Which tracks are on this phone. `AlbumDownloads` answers it. The protocol lets the
/// player ask one question without being given the download code.
///
/// **Asked each time a track is opened**, and never stored by the player. A record
/// downloaded while its queue is playing is read from the phone from the next track.
/// A record removed during the queue is streamed from the next track.
public protocol PhoneCopies: Sendable {
    func copy(of rpmId: String) -> PhoneCopy?
}

extension DownloadBook: PhoneCopies {
    public func copy(of rpmId: String) -> PhoneCopy? {
        held(rpmId).map { PhoneCopy(file: $0.file, kilobits: $0.kilobits) }
    }
}

/// Tracks that a computer on the home network can serve, for an app that reads from one (the TV).
///
/// Asked when a track is opened, after the copies on this device and before any address is
/// signed. A track the computer holds plays from the computer while it is reachable, and from
/// the cloud when it is not. **No default on the player**: an app that left it out would play
/// only the cloud's tracks and show the computer's tracks as failures. An app with no home
/// network uses ``NothingNearby``, which says so explicitly.
@MainActor
public protocol NearbyCopies: AnyObject {
    /// An address on the home network for `track`, or nil to take it from the cloud.
    func address(of track: CloudTrack, on shelf: CloudShelf) async -> URL?

    /// An address returned by ``address(of:on:)`` failed, at the open or part way through.
    /// The source must not return that computer again for a while: the player asks again
    /// next and needs the cloud address.
    func failed(_ address: URL)
}

/// No home network: every track comes from the cloud or this device.
@MainActor
public final class NothingNearby: NearbyCopies {
    public init() {}
    public func address(of track: CloudTrack, on shelf: CloudShelf) async -> URL? { nil }
    public func failed(_ address: URL) {}
}
