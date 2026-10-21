import Foundation
import RPMKit
import RPMAudio

/// The words of what is playing: the sheet the owner chose on a desktop, kept in the cloud,
/// or else the one LRCLIB gives.
///
/// The player screen asks for lyrics only while it is shown, so ordinary listening sends no
/// request to LRCLIB. The lyrics button needs to know whether any lyrics exist before it is
/// pressed, so the screen asks as it appears.
@MainActor
@Observable
public final class LyricsLookup {
    private let lrclib: LrcLibClient

    /// Where the sheet the owner chose is kept. Nil asks LRCLIB only.
    private let cloud: RPMCloudClient?

    /// The words, or `.empty` where there are none.
    public private(set) var sheet: LyricSheet = .empty

    /// Whether an answer is still coming.
    public private(set) var looking = false

    /// The record the sheet belongs to, as its id and shelf, then artist, title, album and
    /// length. The last four are the values sent to LRCLIB. Two records can differ in the length
    /// alone.
    private var asked: String?

    public init(lrclib: LrcLibClient, cloud: RPMCloudClient? = nil) {
        self.lrclib = lrclib
        self.cloud = cloud
    }

    /// Reads the words for `track`, once. `shelf` is the collection the track is on: the cloud
    /// keeps a chosen sheet under the account that owns the track.
    public func read(_ track: CloudTrack?, on shelf: CloudShelf = .own) async {
        // Use the catalogue length, not the player's. LRCLIB matches on length, and the player
        // reports 0 until the track has started.
        let seconds = track?.duration.seconds ?? 0

        guard let track, let title = track.title, !title.isEmpty else {
            sheet = .empty
            asked = nil
            looking = false
            return
        }

        let key = "\(track.rpmId)|\(shelf.ownerId)|\(track.artist ?? "")|\(title)|\(track.album ?? "")|\(Int(seconds))"
        guard key != asked else { return }

        // Set before the await. A second call while the first is still waiting then does not
        // look up the same record twice.
        asked = key
        sheet = .empty
        looking = true

        // The owner's own choice comes first. A track the cloud does not know, a sheet with no
        // timings, or a failed request all fall back to LRCLIB.
        var found = LyricSheet.empty
        if let cloud, !track.rpmId.isEmpty,
           let lrc = try? await cloud.lyricSheet(rpmId: track.rpmId, on: shelf) {
            found = LyricSheet.parse(lrc)
        }
        guard asked == key else { return }
        if !found.isSynced {
            found = await lrclib.sheet(artist: track.artist, title: title,
                                       album: track.album, duration: seconds)
        }

        // The record changed while the lookup was running. Drop this answer.
        guard asked == key else { return }

        sheet = found
        looking = false
    }
}
