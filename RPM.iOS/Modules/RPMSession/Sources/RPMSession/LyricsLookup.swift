import Foundation
import RPMKit
import RPMLibrary
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

    /// Whether the player shows the lyrics in place of the cover.
    ///
    /// `asked` is the user's choice, from the lyrics key. The lyrics are shown while the user
    /// asked for them and this record has timed lyrics, or the lookup for it is still running.
    /// A record with none shows the cover, and the next record with lyrics shows them again.
    ///
    /// **Worked out from the values, not switched by a change.** A new record sets the sheet to
    /// `.empty` while it is looked up, and a record with no lyrics ends the lookup with
    /// `.empty` again. The sheet does not change at the end, so a rule that waits for a change
    /// would leave the empty lyrics screen up, with the lyrics key greyed out and no way to
    /// close it.
    nonisolated public static func shows(asked: Bool, sheet: LyricSheet, looking: Bool) -> Bool {
        asked && (sheet.isSynced || looking)
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
        // timings, or a failed request all fall back to LRCLIB. A starter track is never asked
        // about: the cloud does not hold it (``StarterTracks``).
        var found = LyricSheet.empty
        if let cloud, !track.rpmId.isEmpty, !StarterTracks.isStarter(track.rpmId),
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

    /// The sheet ``read(_:on:)`` would find for `track`: the owner's chosen sheet, else LRCLIB's
    /// for the same names and length. It changes nothing here. The iPhone uses it to have the
    /// words of the next song measured before that song starts, against the sheet it will show.
    public func find(_ track: CloudTrack, on shelf: CloudShelf = .own) async -> LyricSheet {
        guard let title = track.title, !title.isEmpty else { return .empty }

        if let cloud, !track.rpmId.isEmpty, !StarterTracks.isStarter(track.rpmId),
           let lrc = try? await cloud.lyricSheet(rpmId: track.rpmId, on: shelf) {
            let chosen = LyricSheet.parse(lrc)
            if chosen.isSynced { return chosen }
        }
        return await lrclib.sheet(artist: track.artist, title: title,
                                  album: track.album, duration: track.duration.seconds)
    }
}
