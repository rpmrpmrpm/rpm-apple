import Foundation

/// Where one track stands on this phone, whatever album or playlist asked for it.
///
/// A track has one file, and an album and a playlist can share it, so this is a fact about the
/// track and not about a page. See ``AlbumDownloads/track(_:)``.
public enum TrackDownload: Sendable, Equatable {
    /// Not on the phone, and nothing that is still asked for holds it.
    case absent

    /// Wanted, and not started yet.
    case waiting

    /// Wanted, and the store is still making it at the chosen rate. See ``RenditionWait``.
    case preparing

    /// On its way. `fraction` is how much of the track has arrived, from 0 to 1.
    case arriving(fraction: Double)

    /// It failed ``AlbumDownloads/mostGoes`` times and nothing is being tried for it.
    case stuck

    /// It has a file on the phone.
    case onPhone
}

/// The small mark at the end of a song's row on an album page or a playlist page.
///
/// The page's download key already says where the page's own album or playlist stands. The rows
/// add what the key cannot say: which songs are still to come while it downloads, and which songs
/// are on the phone through another album or playlist when it was not asked for.
public enum TrackDownloadMark: Sendable, Equatable {
    /// A faint outline circle: the song waits for its turn.
    case waiting

    /// A turning arc: the store is still making the song at the chosen rate.
    case preparing

    /// A small ring that fills as the song arrives.
    case arriving(fraction: Double)

    /// The downloaded glyph: the song is on the phone.
    case done

    /// The stuck glyph: the song could not be downloaded.
    case stuck

    /// Which mark a row shows, or nil for none.
    ///
    /// - Parameters:
    ///   - page: where the page's own album or playlist stands, or nil when nobody asked for it.
    ///   - track: where the row's song stands. Read only when the answer needs it, so a page that
    ///     shows no marks does not read the songs' states, and is not drawn again when they change.
    public static func of(page: AlbumDownloads.Standing?,
                          track: @autoclosure () -> TrackDownload) -> TrackDownloadMark? {
        switch page {
        case .onPhone:
            // The key says it all. A tick on every row would repeat it.
            return nil

        case nil:
            // Not asked for: only the songs that another album or playlist brought are marked.
            return track() == .onPhone ? .done : nil

        case .downloading, .stuck:
            switch track() {
            case .absent: return nil
            case .waiting: return .waiting
            case .preparing: return .preparing
            case .arriving(let fraction): return .arriving(fraction: fraction)
            case .stuck: return .stuck
            case .onPhone: return .done
            }
        }
    }
}
