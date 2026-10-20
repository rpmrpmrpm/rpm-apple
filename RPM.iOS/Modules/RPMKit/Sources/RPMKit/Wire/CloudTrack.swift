import Foundation

/// One track as the cloud holds it.
///
/// Every optional field follows one rule: absent, empty or zero means "not
/// known", never "zero". Rows written before the catalogue existed carry none of
/// them until a desktop fills them in, and treating a missing `trackNumber` as
/// track 0 puts the track first and draws the album in the wrong order.
public struct CloudTrack: Codable, Hashable, Sendable, Identifiable {
    public let rpmId: String
    public let sha256: String
    public let relativePath: String?
    public let originalSize: Int64
    public let title: String?
    public let artist: String?
    public let album: String?
    public let addedAt: Int64
    public let tags: CloudTrackTags?

    /// When the store last wrote this row, by the store's own clock, in unix
    /// seconds. It makes more than one computer possible: a client compares it
    /// against the stamp it last accepted for the same row, server clock against
    /// server clock, so nothing depends on two computers agreeing about the
    /// time. Zero on rows that have no stamp, which reads as
    /// "never changed since it was uploaded".
    public let updatedAt: Int64

    public var id: String { rpmId }

    public init(
        rpmId: String, sha256: String = "", relativePath: String? = nil,
        originalSize: Int64 = 0, title: String? = nil, artist: String? = nil,
        album: String? = nil, addedAt: Int64 = 0, tags: CloudTrackTags? = nil,
        updatedAt: Int64 = 0
    ) {
        self.rpmId = rpmId; self.sha256 = sha256; self.relativePath = relativePath
        self.originalSize = originalSize; self.title = title; self.artist = artist
        self.album = album; self.addedAt = addedAt; self.tags = tags
        self.updatedAt = updatedAt
    }

    // Written out and not synthesised because every field but the id has to
    // survive being absent. A synthesised decoder throws on a missing key, and
    // older rows lack many of these fields.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpmId        = try c.decode(String.self, forKey: .rpmId)
        sha256       = try c.decodeIfPresent(String.self, forKey: .sha256) ?? ""
        relativePath = try c.decodeIfPresent(String.self, forKey: .relativePath)
        originalSize = try c.decodeIfPresent(Int64.self, forKey: .originalSize) ?? 0
        title        = try c.decodeIfPresent(String.self, forKey: .title)
        artist       = try c.decodeIfPresent(String.self, forKey: .artist)
        album        = try c.decodeIfPresent(String.self, forKey: .album)
        addedAt      = try c.decodeIfPresent(Int64.self, forKey: .addedAt) ?? 0
        tags         = try c.decodeIfPresent(CloudTrackTags.self, forKey: .tags)
        updatedAt    = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }

    /// Track length, or zero when the row has no length yet. The player
    /// still learns the real length once it has parsed the stream; this is what
    /// lets a tracklist show it before playback starts.
    public var duration: Duration {
        guard let seconds = tags?.durationSeconds, seconds > 0 else { return .zero }
        return .seconds(seconds)
    }

    /// Whether the E goes beside the title. A track with no catalogue row at all has
    /// no flag, which is the same answer as a file that carries none.
    public var isExplicit: Bool { tags?.isExplicit ?? false }
}

/// What a file says about its own lyrics.
///
/// Ported from `RPM.Core/Models/TrackInfo.cs`. It is a type here because of a bug:
/// the wire carries a number, and **"not zero" is not the same question as
/// "explicit"**. Two means somebody stated that the record is clean (an edited
/// single, or a record that was never explicit at all), so a badge drawn on
/// `advisory > 0` puts an E on most of a library that carries the flag at all.
public enum ContentAdvisory: Int, Sendable {
    /// No flag. Not the same as clean: nobody has said either way, and it is the
    /// settled answer for a row nobody has read yet as well.
    case unknown = 0

    /// Explicit lyrics, and the only one of the three that shows the E.
    case explicit = 1

    /// Stated to be clean.
    case clean = 2
}

/// The catalogue fields: what a client needs to draw an album rather than a bag of
/// files. Every one is optional and zero means "not known".
///
/// `favorite` is the exception: false is a real answer, because unfavouriting
/// has to travel. It is on the catalogue row and not in the sidecar because
/// the sidecar is one blob per track with the cover inside it, and a phone
/// drawing hearts down a library would otherwise fetch a full-size JPEG per song
/// to find out which songs are loved. The same reason applies to `advisory`.
public struct CloudTrackTags: Codable, Hashable, Sendable {
    public var durationSeconds: Double = 0
    public var trackNumber: Int = 0
    public var trackCount: Int = 0
    public var discNumber: Int = 0
    public var discCount: Int = 0
    public var year: Int = 0
    public var genre: String?
    public var albumArtist: String?

    // What the file IS, as against what it holds. A lossy encode has no bit
    // depth to carry, so zero here is "not applicable" as often as it is "not
    // known", and neither is a number to show.
    public var `extension`: String?
    public var channels: Int = 0
    public var sampleRate: Int = 0
    public var bitsPerSample: Int = 0
    public var bitrateKbps: Int = 0
    public var codecDescription: String?

    // Which composition the track is part of.
    public var work: String?
    public var movementName: String?
    public var movementNumber: Int = 0
    public var composer: String?

    // How loud the recording is, so a track played from the cloud on a phone
    // that has never held the file is levelled with everything around it.
    public var loudnessLufs: Double = 0
    public var truePeak: Double = 0

    public var favorite: Bool = false
    public var favoritedAt: Int64 = 0

    /// Whether the file's own flag calls the lyrics explicit, so the E beside a
    /// title is a fact from the record and not a guess. Zero is unknown,
    /// which is the settled answer for the many files carrying no flag as well
    /// as for a row nobody has read yet: neither draws a badge.
    public var advisory: Int = 0

    // Which RECORD this is, as against which album. A phone has no files to read
    // tags from and nothing it could pick a pressing with, so without these it
    // would ask the shared album entry on artist and title alone and land on a
    // pressing the computer that uploaded the music never had.
    public var catno: String?
    public var barcode: String?
    public var musicBrainzReleaseId: String?
    public var musicBrainzDiscId: String?

    // What kind of release the record is, as the listener or the file set it ("Album", "Ep",
    // "Live"...), or nil where nobody has said. See `ReleaseType` in RPMLibrary.
    public var releaseType: String?

    // The two names that are not their Swift names. Spelled out because the wire
    // is the contract: renaming these to match the C# property rather than the
    // C# [JsonPropertyName] would decode nothing and report no error.
    enum CodingKeys: String, CodingKey {
        case durationSeconds, trackNumber, trackCount, discNumber, discCount
        case year, genre, albumArtist
        case `extension`, channels, sampleRate, bitsPerSample, bitrateKbps, codecDescription
        case work, movementName, movementNumber, composer
        case loudnessLufs, truePeak
        case favorite, favoritedAt, advisory
        case catno, barcode
        case musicBrainzReleaseId = "mbReleaseId"
        case musicBrainzDiscId = "discId"
        case releaseType
    }

    public init() {}

    /// Whether the row knows how loud the recording is. Zero is "not measured":
    /// a real reading is negative, since music sits below full scale and a track
    /// at 0 LUFS would be a square wave.
    public var hasLoudness: Bool { loudnessLufs < 0 }

    /// What the file says about its lyrics, whatever number the wire carried: a
    /// value nothing here knows is read as no flag rather than as a fourth state.
    public var advisoryFlag: ContentAdvisory { ContentAdvisory(rawValue: advisory) ?? .unknown }

    /// Whether the E goes beside the title. **This is the one place to ask it**, so
    /// that nobody writes the "not zero" version of it again.
    public var isExplicit: Bool { advisoryFlag == .explicit }

    /// Whether the row knows what the file is. False on rows written without
    /// the format fields, which is what a catalogue refresh looks for.
    public var hasFormat: Bool {
        !(`extension` ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            || channels > 0 || sampleRate > 0
    }
}

/// What `/artwork` answers with.
///
/// **Only the artist's pictures are used**: the backgrounds, the square thumbs and the logo.
/// The route also carries a cover and a disc picture, and neither is ever taken: a looked-up
/// cover is a guess that cannot be told from a right one, and the desktop does not use it either.
public struct ArtworkLookup: Decodable, Sendable {
    public let backgrounds: [String]

    /// fanart.tv's square artist thumbs, 1000 by 1000, best first. Empty for most artists,
    /// and absent from older servers, which decodes as empty.
    public let thumbs: [String]

    /// The artist's logo: a transparent PNG of their name as they letter it (fanart.tv's HD logo,
    /// else TheAudioDB's). Nil for most artists.
    public let logo: String?

    enum CodingKeys: String, CodingKey { case backgrounds, thumbs, logo }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backgrounds = (try? c.decode([String].self, forKey: .backgrounds)) ?? []
        thumbs = (try? c.decode([String].self, forKey: .thumbs)) ?? []
        logo = try? c.decodeIfPresent(String.self, forKey: .logo)
    }
}

/// Pictures OF an artist, in the two shapes the server keeps apart.
public struct ArtistPictures: Sendable, Equatable {
    /// Press shots, 16:9 (fanart.tv's are 1920 by 1080), best first. For the backdrop behind
    /// the record and the band on the artist page.
    public let backdrops: [URL]

    /// Square pictures (fanart.tv's `artistthumb`, 1000 by 1000), best first. For the boxes
    /// on the artists wall. Empty for most artists.
    public let squares: [URL]

    /// The artist's logo, a transparent PNG, for the title of their page. Nil for most artists.
    /// Not one of the photographs: ``isEmpty`` does not count it.
    public let logo: URL?

    /// True when the API marked the answer as only part of one: a source could not be asked, or had
    /// not answered in time. The API finishes it in the background. Shown, and never kept for the
    /// session: kept, the artist would miss fanart.tv's pictures until the app was restarted.
    public let partial: Bool

    public static let none = ArtistPictures(backdrops: [], squares: [], logo: nil, partial: false)

    /// - Parameter partial: **no default.** Whether the answer may be kept depends on it, and a
    ///   default of "whole" is a mark somebody forgets to pass on.
    public init(backdrops: [URL], squares: [URL], logo: URL?, partial: Bool) {
        self.backdrops = backdrops
        self.squares = squares
        self.logo = logo
        self.partial = partial
    }

    public var isEmpty: Bool { backdrops.isEmpty && squares.isEmpty }
}
