import Foundation
import RPMKit
import RPMAudio

/// The words of what is playing, from LRCLIB.
///
/// The player screen asks for lyrics only while it is shown, so ordinary listening sends no
/// request to LRCLIB. The lyrics button needs to know whether any lyrics exist before it is
/// pressed, so the screen asks as it appears.
@MainActor
@Observable
public final class LyricsLookup {
    private let lrclib: LrcLibClient

    /// The words, or `.empty` where there are none.
    public private(set) var sheet: LyricSheet = .empty

    /// Whether an answer is still coming.
    public private(set) var looking = false

    /// The record the sheet belongs to, as artist, title, album and length. These are the values
    /// sent to LRCLIB. Two records can differ in the length alone.
    private var asked: String?

    public init(lrclib: LrcLibClient) {
        self.lrclib = lrclib
    }

    /// Reads the words for `track`, once.
    public func read(_ track: CloudTrack?) async {
        // Use the catalogue length, not the player's. LRCLIB matches on length, and the player
        // reports 0 until the track has started.
        let seconds = track?.duration.seconds ?? 0

        guard let track, let title = track.title, !title.isEmpty else {
            sheet = .empty
            asked = nil
            looking = false
            return
        }

        let key = "\(track.artist ?? "")|\(title)|\(track.album ?? "")|\(Int(seconds))"
        guard key != asked else { return }

        // Set before the await. A second call while the first is still waiting then does not
        // look up the same record twice.
        asked = key
        sheet = .empty
        looking = true

        let found = await lrclib.sheet(artist: track.artist, title: title,
                                       album: track.album, duration: seconds)

        // The record changed while the lookup was running. Drop this answer.
        guard asked == key else { return }

        sheet = found
        looking = false
    }
}
