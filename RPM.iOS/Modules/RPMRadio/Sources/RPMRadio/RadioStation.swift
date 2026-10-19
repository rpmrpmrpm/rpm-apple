import Foundation

/// One internet radio station, as the app knows it.
///
/// Matches `RPM.Core/Radio/RadioStation.cs` in the desktop app. The shape follows the
/// directory (Radio Browser), reduced to what a player needs: a stable id to save it by, a name,
/// a URL to open, and enough context to choose between two stations with the same name.
///
/// **All the fields that the directory reports are kept, and no others.** A saved station still
/// plays when the directory no longer lists it, because the URL is stored with the preset and is
/// not looked up again.
public struct RadioStation: Codable, Hashable, Sendable, Identifiable {
    /// The directory's id. It stays the same when the name or URL changes, and a preset is
    /// stored under it.
    public let uuid: String

    public let name: String

    /// Where the audio is. This is the directory's *resolved* URL where it has one: the
    /// station's own address after redirects and playlist unwrapping. It is preferred because it
    /// still works when the station's public domain has expired.
    public let streamUrl: String

    public var homepage: String?
    public var favicon: String?

    /// The other logos that the directory has for this station, best first. The view that draws
    /// a logo tries them in order.
    ///
    /// **Why there is more than one.** The directory files a stream, not a station, and the
    /// several rows for one broadcaster carry different pictures. For example, the 192k stream of
    /// NPO Radio 1 points to a Wikimedia file that is not served without browser credentials,
    /// and its 64k stream points to a plain PNG on the station's own site that works. A URL
    /// cannot be classified without requesting it, so ``RadioResults`` keeps all of them, and a
    /// view that fails on the first one tries the next.
    ///
    /// **This describes a directory answer, not a station**, so it is not saved with a preset.
    /// A preset is one stream that the user chose. The list is built again each time the
    /// directory is asked.
    public var otherLogos: [String] = []

    /// The uuids of the directory rows that were folded into this one, not including its own.
    ///
    /// **What it is for.** A station reaches the list as several rows, and ``RadioResults``
    /// keeps one of them. A check by uuid would give the wrong answer for each row that was not
    /// kept. For example, "NPO 2" and "NPO Radio 2" are one icecast mount filed twice, so hiding
    /// the first row in the admin would not hide the second. Matches `RadioStation.AlsoFiledAs`
    /// in the desktop app.
    ///
    /// Not saved with a preset, for the same reason as ``otherLogos``.
    public var alsoFiledAs: [String] = []

    /// Whether this row is the station with that uuid, under any of the uuids that the directory
    /// uses for it.
    public func isFiled(as uuid: String) -> Bool {
        self.uuid.caseInsensitiveCompare(uuid) == .orderedSame
            || alsoFiledAs.contains { $0.caseInsensitiveCompare(uuid) == .orderedSame }
    }

    public var country: String?

    /// ISO 3166-1 alpha-2 country code. The directory filters on this value.
    public var countryCode: String?

    public var language: String?

    /// Genre tags in lower case, as the directory's contributors entered them.
    public var tags: [String] = []

    public var codec: String?

    /// Advertised bitrate in kbps. Zero when the station does not state one.
    public var bitrateKbps: Int = 0

    /// The number of votes that the directory's users gave this station.
    public var votes: Int = 0

    /// How often the directory has given this station to a client. This is the default order. It
    /// is the nearest measure of popularity that needs no account.
    public var clickCount: Int = 0

    /// True when the stream is HLS rather than a plain ICY/HTTP one. It plays, but it
    /// carries no ICY metadata, so there is no live track title from one.
    public var isHls = false

    /// The result of the directory's last check of the stream. False does not prove that the
    /// stream is down, because a station can be up between checks, but it should not be offered
    /// first.
    public var reachable = true

    /// The name to show instead of ``name``, where the list that holds this station has found
    /// that the plain name would look the same as another station's.
    ///
    /// **This describes a list, not a station**, so it is not saved with a preset, and the next
    /// list is different. See ``RadioNames/distinguish(_:)``.
    public var shownName: String?

    /// The admin's edit, applied when the station is drawn (``StationRules/shown(_:)``). ``name``
    /// and ``tags`` keep the directory's values, so a preset is saved and folded as the directory
    /// files it. **This depends on rpm's rules at the time of drawing**, so it is not saved with
    /// a preset.
    public var edit: StationEdit?

    public var id: String { uuid }

    public init(uuid: String, name: String, streamUrl: String) {
        self.uuid = uuid
        self.name = name
        self.streamUrl = streamUrl
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, name, streamUrl, homepage, favicon, country, countryCode
        case language, tags, codec, bitrateKbps, votes, clickCount, isHls, reachable
    }

    // MARK: What a row shows

    /// The name to show: ``name`` without the stream's specification and its slogan.
    /// "PureClassixx #Flac" is a station called PureClassixx. The admin's title comes first
    /// where there is one.
    ///
    /// This value is derived. ``name`` stays as the directory has it, because the raw name is
    /// used to save a preset, to fold two rows for one station, and to search. Only the display
    /// changes.
    public var display: String { edit?.name ?? shownName ?? RadioNames.clean(name) }

    /// The tags that the station is filed under for genres: the admin's tags where the admin set
    /// some, otherwise the directory's.
    public var shownTags: [String] { edit?.tags ?? tags }

    /// The genre tags worth showing: ``shownTags`` without the tags that describe the stream's
    /// specification or that the directory uses for its own bookkeeping.
    public var genres: [String] { RadioNames.genres(shownTags) }

    /// The codec alone, for example "MP3", "AAC+" or "FLAC".
    ///
    /// The bitrate is left out on purpose. It differs between the streams of one station, and a
    /// listener does not choose by it, while the codec is the one word that listeners use.
    public var format: String {
        (codec?.isEmpty == false) ? codec!.uppercased() : ""
    }

    /// The format line, for example "MP3 128k". Empty when the station states neither a codec
    /// nor a bitrate.
    public var quality: String {
        let named = codec?.trimmingCharacters(in: .whitespaces).isEmpty == false
        switch (named, bitrateKbps > 0) {
        case (true, true): return "\(codec!.uppercased()) \(bitrateKbps)k"
        case (true, false): return codec!.uppercased()
        case (false, true): return "\(bitrateKbps)k"
        case (false, false): return ""
        }
    }

    /// The three or four letters shown on the dial card.
    public var sign: String { StationSign.of(name) }

    /// Every logo that the directory has for this station, best guess first. The extra logos are
    /// the ones that ``RadioResults`` gathered from the station's other streams.
    ///
    /// This is one list and not a favicon plus a second field at each call site. The row, the
    /// mini player and the large tile therefore try the logos in the same order and show the
    /// same picture for one station.
    public var logos: [String] {
        guard let favicon, !favicon.isEmpty else { return otherLogos }
        return [favicon] + otherLogos
    }
}
