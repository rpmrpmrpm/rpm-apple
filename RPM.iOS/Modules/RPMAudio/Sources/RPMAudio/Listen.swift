import Foundation

/// Whether something that was played counts as having been listened to.
///
/// Flicking through an album touches every track on it for a second or two. If those counted as
/// plays, "most played" would list the tracks that were skipped fastest, which is the opposite of
/// its purpose. The error is hard to notice because the numbers look plausible.
///
/// The rule is the one used by scrobbling services: half the track, or four minutes, whichever
/// comes first. Half is fair for both a two-minute single and a twenty-minute side. Four minutes
/// stops a long side from needing ten. A track shorter than thirty seconds never counts.
///
/// **This is a port of `RPM.Core/Playback/Listen.cs` and must stay identical to it.** The plays
/// counted on the phone and on the desktop are added together into one number per track. If the
/// phone counted a play at ten seconds, every total on the desktop would be too high, and nothing
/// on either screen would show why.
public enum Listen {
    /// A track shorter than this is never counted as a play.
    public static let shortestSeconds: Double = 30

    /// A listen shorter than this is not recorded at all, neither as a play nor as a skip.
    /// Flicking down a wall of tracks ends one listen per track after a second or two.
    public static let noticedSeconds: Double = 5

    /// The most that can be required for a listen: however long the record is, this much counts.
    public static let enoughSeconds: Double = 4 * 60

    /// Whether a finished listen is worth recording at all.
    ///
    /// This is deliberately wider than ``counts(heard:length:)``. A listen that did not count is
    /// the evidence for "keeps skipping this", and it is the only evidence the app has that
    /// somebody dislikes a track.
    public static func worthRecording(heard: Double, length: Double) -> Bool {
        length >= shortestSeconds && heard >= noticedSeconds
    }

    /// Whether `heard` seconds of a track `length` seconds long is a play.
    ///
    /// - Parameter heard: Audio actually delivered, not the position reached. A seek changes the
    ///   position but not the audio delivered, and the audio delivered is what the user heard. A
    ///   record that passed through in silence arrives here with zero and cannot become the most
    ///   played track in the library.
    /// - Parameter length: Zero when the catalogue has no duration for the track (a row that has
    ///   not been filled in yet). Nothing counts then. Guessing a length would count quick
    ///   skips past tracks with no known duration, and a phone sees those rows first.
    public static func counts(heard: Double, length: Double) -> Bool {
        guard length >= shortestSeconds, heard > 0 else { return false }
        return heard >= min(length / 2, enoughSeconds)
    }
}
