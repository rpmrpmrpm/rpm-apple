import Foundation

/// What `metadata/plays` answers with: one record's tracks as MusicBrainz lists them, and how many
/// times the world has played each recording (ListenBrainz's counts). Mirrors `CatalogPlays` in
/// `RPM.Fingerprint/Catalog/CatalogContracts.cs`.
///
/// Empty is an answer: the catalogues were asked and do not have the record. A failure is thrown by
/// the client instead (the API answers 503), so the two never arrive as one value.
public struct RecordPlays: Decodable, Sendable, Equatable {
    /// One track of the release: where it sits on its disc, and the recording the counts
    /// belong to.
    public struct Track: Decodable, Sendable, Equatable {
        public let position: Int
        public let title: String
        public let recordingMbid: String

        public init(position: Int, title: String, recordingMbid: String) {
            self.position = position
            self.title = title
            self.recordingMbid = recordingMbid
        }
    }

    /// How many times one recording has been played, and by how many people.
    public struct Plays: Decodable, Sendable, Equatable {
        public let recordingMbid: String
        public let listens: Int64
        public let listeners: Int

        public init(recordingMbid: String, listens: Int64, listeners: Int) {
            self.recordingMbid = recordingMbid
            self.listens = listens
            self.listeners = listeners
        }
    }

    public let tracks: [Track]
    public let plays: [Plays]

    public static let empty = RecordPlays(tracks: [], plays: [])

    public init(tracks: [Track], plays: [Plays]) {
        self.tracks = tracks
        self.plays = plays
    }

    enum CodingKeys: String, CodingKey { case tracks, plays }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = (try? c.decode([Track].self, forKey: .tracks)) ?? []
        plays = (try? c.decode([Plays].self, forKey: .plays)) ?? []
    }

    /// The listens of each track, by disc and position on the disc.
    ///
    /// **By position, not by title**, for the reason the desktop's `TrackPopularity.PlaysByPosition`
    /// gives: the catalogue spells titles its own way, and a match on the words drops the tracks it
    /// is least sure about, which on a famous record are the famous ones.
    ///
    /// **The disc is counted from the listing.** The API sends the tracks in pressing order with each
    /// position counted on its own disc, and no disc number. A position that does not follow the one
    /// before it starts the next disc. Matched on position alone, track 3 of a second disc would
    /// overwrite track 3 of the first.
    ///
    /// A track the counts say nothing about is absent and not zero.
    public var listensByPlace: [TrackPlace: Int64] {
        var byRecording: [String: Int64] = [:]
        for row in plays { byRecording[row.recordingMbid.lowercased()] = row.listens }

        var places: [TrackPlace: Int64] = [:]
        var disc = 1
        var last = 0
        for track in tracks where track.position > 0 {
            if track.position <= last { disc += 1 }
            last = track.position

            if let listens = byRecording[track.recordingMbid.lowercased()] {
                places[TrackPlace(disc: disc, position: track.position)] = listens
            }
        }
        return places
    }
}

/// Where a track sits on a record: its disc, counted from one, and its position on that disc.
public struct TrackPlace: Hashable, Sendable {
    public let disc: Int
    public let position: Int

    public init(disc: Int, position: Int) {
        self.disc = disc
        self.position = position
    }
}
