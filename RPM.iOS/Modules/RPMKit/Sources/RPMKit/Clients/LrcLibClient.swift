import Foundation

/// LRCLIB's answer to "what is being sung, and when". See <https://lrclib.net>.
///
/// This follows `RPM.Core/Lyrics/LrcLibLookup.cs` on the desktop. LRCLIB was chosen there because it
/// needs nothing: no key, no account, no quota. In return it asks for an honest User-Agent. MusicBrainz
/// asks for the same, and this app sends one.
///
/// **The duration is what makes this accurate.** Two recordings can share an artist and a title and still
/// differ in length by four minutes. Examples are a single edit and an album cut, or a live take and the
/// studio version. A sheet written for one of them drifts out of step with the other. LRCLIB matches on
/// length as well as name. So the exact lookup is tried first, and its answer is trusted. The search
/// fallback runs only when that finds nothing. A search result is used only if its length is close enough
/// for the words to line up.
///
/// **Everything here is optional.** No path throws. Every failure gives the same result, which is no sheet.
/// Examples are no network, no match, or words without timings. A screen handles all of them the same way.
public struct LrcLibClient: Sendable {
    private static let base = URL(string: "https://lrclib.net/api/")!

    /// The largest length difference, in seconds, that is accepted when the record's length is known.
    /// Above this, the timings are assumed to belong to a different cut. LRCLIB's own matching uses about
    /// this tolerance.
    private static let slack: Double = 2.5

    private let wire: Gated
    private let userAgent: String

    /// - Parameter reach: The same gate that every other request uses. There is no default. Lyrics are
    ///   optional, and a screen works without them. But a lyric request that waits a full timeout on a
    ///   dead network would stop the screen from drawing.
    /// - Parameter userAgent: Names the app and gives a way to contact its author. LRCLIB asks for this.
    ///   A request with no name is not welcome.
    public init(reach: NetworkReach, session: URLSession = Wire.session(),
                userAgent: String = "RPM/1.0 (https://rpmrpmrpm.com)") {
        self.wire = Gated(reach: reach, session: session)
        self.userAgent = userAgent
    }

    /// The synced sheet for one recording, or `.empty` if there is none.
    ///
    /// - Parameter duration: The record's length in seconds. Zero or less skips the exact lookup and
    ///   widens the fallback. A stream with no known length needs that.
    public func sheet(artist: String?, title: String?, album: String?,
                      duration: Double) async -> LyricSheet {
        // The title is the one thing that cannot be guessed. An artist can be missing for a loose file,
        // and the search still finds the track. A track with no title cannot be looked up at all.
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .empty
        }

        if duration > 0 {
            let exact = await get(artist: artist, title: title, album: album, duration: duration)
            if exact.isSynced { return exact }
        }

        return await search(artist: artist, title: title, duration: duration)
    }

    /// The exact lookup, by name and length together. Its result can be trusted outright.
    private func get(artist: String?, title: String, album: String?,
                     duration: Double) async -> LyricSheet {
        let path = "get?track_name=\(escaped(title))&artist_name=\(escaped(artist))"
            + "&album_name=\(escaped(album))&duration=\(Int(duration.rounded()))"

        guard let json = await ask(path) else { return .empty }
        return Self.read(json)
    }

    /// The fallback search. Its result cannot be fully trusted. A search returns everything that resembles
    /// the name, so each candidate's length is checked against the record's length before its timings are used.
    private func search(artist: String?, title: String, duration: Double) async -> LyricSheet {
        let path = "search?track_name=\(escaped(title))&artist_name=\(escaped(artist))"

        guard let json = await ask(path),
              let candidates = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]]
        else { return .empty }

        for candidate in candidates {
            if duration > 0, let theirs = candidate["duration"] as? Double,
               abs(theirs - duration) > Self.slack {
                continue
            }

            let sheet = Self.read(candidate)
            if sheet.isSynced { return sheet }
        }

        return .empty
    }

    /// Makes one request. **Nothing is thrown.** A 404 is the normal answer when nobody has written the
    /// lyrics down. To the screen it means the same as no network.
    private func ask(_ path: String) async -> Data? {
        guard let url = URL(string: path, relativeTo: Self.base) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, http) = try? await wire.fetch(request, method: "GET"),
              (200..<300).contains(http.statusCode)
        else { return nil }

        return data
    }

    /// Reads one LRCLIB record. **Only `syncedLyrics` is read.** `plainLyrics` is words without timing.
    /// A view that scrolls with the music cannot use them.
    private static func read(_ json: Data) -> LyricSheet {
        guard let record = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { return .empty }

        return read(record)
    }

    private static func read(_ record: [String: Any]) -> LyricSheet {
        LyricSheet.parse(record["syncedLyrics"] as? String)
    }

    private func escaped(_ value: String?) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return (value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
