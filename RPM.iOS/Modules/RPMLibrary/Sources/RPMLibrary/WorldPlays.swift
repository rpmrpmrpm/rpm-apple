import Foundation
import RPMKit

/// The play counts for each song on a record, from the RPM API (`metadata/plays`).
/// The counts are kept in memory for the session.
///
/// The memory is not saved to disk. The server caches each answer for everyone, so a
/// request for the same record after a launch is a fast cached request.
///
/// **A complete answer is kept. A failure is not kept, and a partial answer is not kept
/// either.** A record that the catalogues do not have gives an empty answer, and that
/// answer is kept. This stops the record being requested on every visit. A request that
/// could not be made returns nil, and the next call tries again. An answer that the API
/// marks as partial is returned to the caller but not kept. The API finishes the answer
/// after the request ends.
///
/// This runs on the main actor, so a page can read what is kept while it is being built
/// (``cached(_:)``). The request itself runs in a separate task. Closing a page does not
/// cancel that task, so the answer is ready the next time the record is opened.
@MainActor
public final class WorldPlays {
    /// One record, as the plays route is asked about it.
    public struct Record: Hashable, Sendable {
        public let artist: String
        public let album: String
        public let tracks: Int
        public let release: String?

        public init(artist: String, album: String, tracks: Int, release: String?) {
            self.artist = artist
            self.album = album
            self.tracks = tracks
            self.release = release
        }

        /// Builds a record from a library album, in the form the desktop's sweep uses.
        /// That is the album artist, the title, the number of songs, and the MusicBrainz
        /// release ID from the tags, if there is one.
        public init(_ album: CloudAlbum) {
            self.init(artist: album.artist, album: album.album, tracks: album.tracks.count,
                      release: album.tracks.lazy
                          .compactMap { $0.tags?.musicBrainzReleaseId }
                          .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }

    public typealias Fetch = @Sendable (Record) async throws -> (plays: RecordPlays, partial: Bool)

    private let fetch: Fetch
    private var known: [Record: [TrackPlace: Int64]] = [:]
    private var running: [Record: Task<[TrackPlace: Int64]?, Never>] = [:]

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    public convenience init(client: RPMCloudClient) {
        self.init { record in
            try await client.recordPlays(artist: record.artist, album: record.album,
                                         tracks: record.tracks, release: record.release)
        }
    }

    /// The play counts by disc and track position, if this record has been fetched in
    /// this session. Otherwise `nil`.
    public func cached(_ record: Record) -> [TrackPlace: Int64]? { known[record] }

    /// The play counts by disc and track position, from memory or from the API.
    /// Returns an empty dictionary when the catalogues do not have the record. Returns
    /// `nil` when the request could not be made.
    public func plays(_ record: Record) async -> [TrackPlace: Int64]? {
        if let kept = known[record] { return kept }
        if let out = running[record] { return await out.value }

        let fetch = self.fetch
        let ask = Task { [weak self] () -> [TrackPlace: Int64]? in
            let answer = try? await fetch(record)
            self?.running[record] = nil

            guard let answer else { return nil }
            let places = answer.plays.listensByPlace
            if !answer.partial { self?.known[record] = places }
            return places
        }

        running[record] = ask
        return await ask.value
    }

    /// Called on sign-out. The records kept here belong to the account that is signing
    /// out.
    public func forget() {
        known = [:]
    }
}
