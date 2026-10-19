import Foundation
import RPMKit

/// The library the screens show: every track in the cloud, and every track that a paired computer
/// on the network holds and the cloud does not, as one list. A track in both places is one track,
/// matched by `rpmId`. The cloud's row is kept, and where the track plays from is decided when it
/// is opened. A track on two computers is taken from the computer whose key sorts first. The
/// Android TV app's `HomeMerge` follows the same rules, so change both if the rules change.
public enum HomeMerge {
    public static func merge(_ cloud: [CloudTrack], _ catalogs: [HeldCatalog]) -> [CloudTrack] {
        guard !catalogs.isEmpty else { return cloud }
        var seen = Set(cloud.map(\.rpmId))
        var merged = cloud
        // Sorted by computer key, so the merge gives the same result on every launch.
        for catalog in catalogs.sorted(by: { $0.computer < $1.computer }) {
            for track in catalog.tracks.values.sorted(by: { $0.rpmId < $1.rpmId })
            where seen.insert(track.rpmId).inserted {
                merged.append(asCloudTrack(track))
            }
        }
        return merged
    }

    /// A computer's track in the shape the library is built from.
    public static func asCloudTrack(_ track: PeerTrack) -> CloudTrack {
        var tags = CloudTrackTags()
        tags.durationSeconds = track.seconds
        tags.trackNumber = track.track
        tags.discNumber = track.disc
        tags.year = track.year
        tags.genre = track.genre
        tags.albumArtist = track.albumArtist
        tags.extension = track.container.isEmpty ? nil : track.container
        tags.codecDescription = track.codec
        tags.advisory = track.advisory
        return CloudTrack(rpmId: track.rpmId, relativePath: track.path, originalSize: track.size,
                          title: track.title, artist: track.artist, album: track.album,
                          addedAt: PeerWire.unixSeconds(ticks: track.added), tags: tags)
    }
}
