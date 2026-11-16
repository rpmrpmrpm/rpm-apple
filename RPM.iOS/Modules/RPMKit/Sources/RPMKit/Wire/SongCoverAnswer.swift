import Foundation

/// What the API answered when asked for the cover of a song a station announces
/// (``RPMCloudClient/songCover(artist:title:size:)``).
public enum SongCoverAnswer: Equatable, Sendable {
    /// The cover's address.
    case found(URL)

    /// The API looked and found no cover for the song.
    case none

    /// The ask got no answer about the song: no network, a refusal, or a body that could not be read.
    case failed

    /// The API is still looking (503). It finishes in the background and answers the next ask.
    case busy
}
