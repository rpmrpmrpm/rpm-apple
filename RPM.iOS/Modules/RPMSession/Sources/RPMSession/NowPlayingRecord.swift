// RemoteControl updates the system's Now Playing display. macOS builds of this package do not
// have it, so the whole file is excluded there.
#if os(iOS) || os(tvOS)
import Foundation
import RPMKit
import RPMLibrary
import RPMArt
import RPMAudio
import RPMRadio

/// What is playing, as the screens draw it: the record with both of its pictures, in one value
/// that is replaced as a whole. The system Now Playing display is kept in step with it.
///
/// One value rather than separate fields, so the cover and the disc always belong to the same
/// track. The record on screen may change its face only while the record is not playing. See
/// ``PlayingRecord``.
@MainActor
@Observable
public final class NowPlayingRecord {
    private let session: LibrarySession
    private let artwork: ArtworkStore
    private let player: Player
    private let remote: RemoteControl

    public private(set) var playing: PlayingRecord?

    /// The cover alone. Derived from ``playing``, so it cannot disagree with the record.
    public var art: CoverArt? { playing?.art }

    /// The edge length the pictures are requested at: the larger of the sizes the screens draw.
    private let edge: Int

    public init(session: LibrarySession, artwork: ArtworkStore, player: Player,
                remote: RemoteControl, edge: Int) {
        self.session = session
        self.artwork = artwork
        self.player = player
        self.remote = remote
        self.edge = edge
    }

    /// The track changed. Finds the cover and disc of its record and shows them.
    public func show(_ track: CloudTrack?) async {
        guard let track else {
            playing = nil
            remote.show(nil, artwork: nil)
            return
        }

        remote.show(track, artwork: art?.image)

        // Uses the record from the shelf when it is there. Otherwise a record is built from this
        // track. The store only uses the key, which is the same in both cases.
        let key = AlbumGrouping.key(for: track)
        let album = session.albums.first(where: { $0.key == key })
            ?? CloudAlbum(key: key, album: track.album ?? "", artist: track.artist ?? "",
                          tracks: [track])

        let shelf = session.shelves.shelf(ofAlbum: album)

        // Both are requested at once and shown together. A disc that arrives after its cover
        // would count as a second change of record.
        async let asked = artwork.cover(for: album, on: shelf, edge: edge)
        async let askedDisc = artwork.disc(for: album, on: shelf, edge: edge)

        let (got, disc) = await (asked, askedDisc)

        // The track changed while the requests were running. This is checked once, so the cover
        // and the disc are always set together.
        guard player.current?.rpmId == track.rpmId else { return }

        playing = PlayingRecord(album: track.album ?? "", art: got, disc: disc)
        remote.show(track, artwork: got?.image)
    }

    /// A station was tuned in or cleared. A station is shown under its own name, with no
    /// pictures. Tuning a station counts as a record change, so the disc of the last album is
    /// removed.
    public func show(station: RadioStation?) {
        playing = station.map { PlayingRecord.bare($0.display) }
        remote.show(station: station)
    }

    /// Forgets the record, for signing out.
    public func forget() {
        playing = nil
    }
}
#endif
