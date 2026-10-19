import Foundation
import RPMKit

/// One tag to ask the directory for, and how to match it.
///
/// The name and the match mode are kept together because they give different results. Matched
/// whole, "hop" finds only stations tagged exactly "hop", and there are none. Matched as a part
/// of a tag, the same word finds "hiphop", "hip hop" and "hip-hop", which are three spellings of
/// one genre. A caller that names a tag must say which mode it wants.
public struct StationTag: Equatable, Sendable {
    public let name: String
    public let whole: Bool

    /// Stations with a tag equal to this name: "jazz" finds "jazz" and not "jazz funk".
    public static func exactly(_ name: String) -> StationTag { StationTag(name: name, whole: true) }

    /// Stations with any tag that contains this word: "metal" also finds "heavy metal",
    /// "metalcore" and "death metal".
    public static func holding(_ name: String) -> StationTag { StationTag(name: name, whole: false) }
}

/// What to ask the directory for. Every field is optional. An empty query returns the most
/// listened-to stations, which is what the radio page shows first.
public struct RadioQuery: Equatable, Sendable {
    /// Substring of the station's name. The directory matches case-insensitively.
    public var name: String?

    /// One genre tag, such as "jazz" or "drum and bass", and whether the directory must match
    /// it whole.
    public var tag: StationTag?

    /// ISO 3166-1 alpha-2 country code.
    public var countryCode: String?

    /// Language name as the directory spells it, for example "english" or "dutch".
    public var language: String?

    public var limit = 120
    public var offset = 0

    public init(name: String? = nil, tag: StationTag? = nil, countryCode: String? = nil,
                language: String? = nil, limit: Int = 120, offset: Int = 0) {
        self.name = name
        self.tag = tag
        self.countryCode = countryCode
        self.language = language
        self.limit = limit
        self.offset = offset
    }
}

/// A genre tag or a country, with the number of stations that have it. The count lets a filter
/// list show the largest entries first.
public struct RadioFacet: Equatable, Sendable, Identifiable {
    public let name: String
    public let code: String
    public let stationCount: Int

    public var id: String { code }

    public init(name: String, code: String, stationCount: Int) {
        self.name = name
        self.code = code
        self.stationCount = stationCount
    }
}

/// Every mirror failed. The directory is down, or the device has no internet connection. In both
/// cases there is no station list to show, and only the saved stations are available.
public struct RadioDirectoryUnavailable: Error, Sendable {
    public let last: String?
    public init(last: String?) { self.last = last }
}

/// The station directory: [Radio Browser](https://api.radio-browser.info).
///
/// Matches `RPM.Core/Radio/RadioBrowserClient.cs` in the desktop app. Radio Browser is used
/// because it needs no API key, its data is CC0, and no other open station directory is
/// available. It is community-run, so the client never depends on one host: the service is a
/// pool of volunteer mirrors, and any of them can be down. A call tries the mirrors in turn
/// until one answers, and remembers which one did.
///
/// An actor, because the preferred mirror is state that two searches can write at the same time.
public actor RadioBrowserClient {
    /// The mirrors to try first. `all.` is the pool's DNS round-robin and answers most of the
    /// time. The named mirrors are the fallback for when its DNS record is out of date. The live
    /// list from the directory replaces this list after a call succeeds, so a mirror that is
    /// renamed or retired stops being tried without an app update.
    private static let seedHosts = [
        "all.api.radio-browser.info",
        "de1.api.radio-browser.info",
        "de2.api.radio-browser.info",
        "at1.api.radio-browser.info",
        "nl1.api.radio-browser.info",
    ]

    private var hosts = seedHosts
    private var preferred = seedHosts[0]

    private let wire: Gated

    /// - Parameter reach: the app's network gate. It has no default. After a failure this
    ///   client tries every mirror it knows, so without the gate a dead network would cost
    ///   one timeout per mirror instead of one timeout in total.
    /// - Parameter agent: the `User-Agent` value. The directory is run by volunteers and asks
    ///   callers to identify themselves, so that it can tell a busy app from a runaway script.
    public init(reach: NetworkReach, agent: String = "RPM/1.0 (iOS)") {
        let settings = Wire.session().configuration
        settings.httpAdditionalHeaders = (settings.httpAdditionalHeaders ?? [:])
            .merging(["User-Agent": agent]) { _, new in new }

        self.wire = Gated(reach: reach, session: URLSession(configuration: settings))
    }

    /// Stations matching `query`, most listened-to first. Stations marked as broken are left out.
    public func search(_ query: RadioQuery) async throws -> [RadioStation] {
        var path = "json/stations/search?hidebroken=true&order=clickcount&reverse=true"

        append(&path, "name", query.name)
        if let tag = query.tag, !tag.name.isEmpty {
            append(&path, "tagExact", tag.whole ? "true" : "false")
            append(&path, "tag", tag.name)
        }
        append(&path, "countrycode", query.countryCode)
        append(&path, "language", query.language)
        append(&path, "limit", String(min(max(query.limit, 1), 1000)))
        if query.offset > 0 { append(&path, "offset", String(query.offset)) }

        let said: [StationSaid] = try await get(path)
        return said.compactMap(station(from:))
    }

    /// The stations with these uuids (`json/stations/byuuid`), including broken ones. These are
    /// the stations the admin filed under a genre that their directory tags do not name, so a
    /// genre search never returns them. The uuids are sent 100 at a time.
    public func byUuid(_ uuids: [String]) async throws -> [RadioStation] {
        let wanted = uuids.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var found: [RadioStation] = []
        for start in stride(from: 0, to: wanted.count, by: 100) {
            let chunk = wanted[start..<min(start + 100, wanted.count)]
            let list = chunk.map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }
            let said: [StationSaid] = try await get("json/stations/byuuid?uuids=" + list.joined(separator: ","))
            found += said.compactMap(station(from:))
        }
        return found
    }

    /// The genre tags worth showing, largest first. Small tags are cut: the directory holds tens
    /// of thousands of tags, and almost all of them are typos with one station each.
    public func tags(atLeast stations: Int = 200) async throws -> [RadioFacet] {
        let said: [FacetSaid] = try await get("json/tags")

        return said
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                      && $0.stationcount >= stations }
            .sorted { $0.stationcount > $1.stationcount }
            .map { RadioFacet(name: $0.name, code: $0.name, stationCount: $0.stationcount) }
    }

    /// The countries that have stations, the one with most stations first.
    public func countries() async throws -> [RadioFacet] {
        let said: [CountrySaid] = try await get("json/countries")

        return said
            .filter { !$0.name.isEmpty && !($0.iso_3166_1 ?? "").isEmpty }
            .sorted { $0.stationcount > $1.stationcount }
            .map { RadioFacet(name: $0.name, code: $0.iso_3166_1!.uppercased(),
                              stationCount: $0.stationcount) }
    }

    /// Tells the directory that a station was played.
    ///
    /// The directory builds its ranking from these calls: the click counts that every app sorts
    /// by are the number of reports. A client that never reports back only uses the ranking and
    /// does not add to it. The call is best-effort: it never throws and never delays tuning.
    public func reportPlayed(_ uuid: String) async {
        guard !uuid.isEmpty else { return }
        let escaped = uuid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? uuid
        _ = try? await get("json/url/\(escaped)") as ClickSaid
    }

    /// Replaces the mirror list with the live list from the directory. It is called after a
    /// successful call, so a failure here only means the list is not refreshed this time.
    public func refreshMirrors() async {
        guard let said: [ServerSaid] = try? await get("json/servers") else { return }

        var seen: [String] = []
        for name in said.map(\.name) where !name.isEmpty && !seen.contains(name) {
            seen.append(name)
        }
        if !seen.isEmpty { hosts = seen }
    }

    // MARK: One GET, against whichever mirror answers

    /// Tries the mirror that worked last first, then the others in order. The first success
    /// also stores its host as the preferred one. The error reaches the caller only when every
    /// mirror has failed.
    private func get<T: Decodable>(_ path: String) async throws -> T {
        var last: String?

        for host in ordered() {
            try Task.checkCancellation()

            guard let url = URL(string: "https://\(host)/\(path)") else { continue }

            do {
                let (data, http) = try await wire.fetch(URLRequest(url: url), method: "GET")

                guard (200..<300).contains(http.statusCode) else {
                    last = "mirror \(host) answered \(http.statusCode)"
                    continue
                }

                let said = try JSONDecoder().decode(T.self, from: data)
                preferred = host
                return said
            } catch is CancellationError {
                throw CancellationError()
            } catch RPMError.offline {
                // The device is offline, so the mirrors are not the problem. Trying the rest
                // would give the same failure again for each one.
                throw RadioDirectoryUnavailable(last: nil)
            } catch {
                last = error.localizedDescription   // this mirror failed; try the next
            }
        }

        throw RadioDirectoryUnavailable(last: last)
    }

    /// The mirror that worked last, then all the others. The preferred mirror is not repeated.
    private func ordered() -> [String] {
        [preferred] + hosts.filter { $0.caseInsensitiveCompare(preferred) != .orderedSame }
    }

    private func append(_ path: inout String, _ key: String, _ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let escaped = value.trimmingCharacters(in: .whitespaces)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
        path += "&\(key)=\(escaped)"
    }

    // MARK: What the directory sends

    /// Returns `nil` for a record that cannot be played or told apart from others: no URL, no
    /// name or no id.
    nonisolated func station(from said: StationSaid) -> RadioStation? {
        let url = (said.url_resolved?.isEmpty == false) ? said.url_resolved! : (said.url ?? "")

        guard !url.trimmingCharacters(in: .whitespaces).isEmpty,
              let name = said.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let uuid = said.stationuuid, !uuid.isEmpty
        else { return nil }

        var made = RadioStation(uuid: uuid, name: name,
                                streamUrl: url.trimmingCharacters(in: .whitespaces))
        made.homepage = blank(said.homepage)
        made.favicon = blank(said.favicon)
        made.country = blank(said.country)
        made.countryCode = blank(said.countrycode)?.uppercased()
        made.language = blank(said.language)
        made.tags = Self.splitTags(said.tags)
        made.codec = blank(said.codec)
        made.bitrateKbps = max(0, said.bitrate ?? 0)
        made.votes = max(0, said.votes ?? 0)
        made.clickCount = max(0, said.clickcount ?? 0)
        made.isHls = (said.hls ?? 0) != 0
        made.reachable = (said.lastcheckok ?? 1) != 0
        return made
    }

    private nonisolated func blank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespaces)
    }

    /// Splits the directory's tags, which come as one comma-separated string that can contain
    /// blank and duplicate entries. Returns lower-case tags without blanks or duplicates.
    public static func splitTags(_ tags: String?) -> [String] {
        guard let tags, !tags.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        var seen: [String] = []
        for raw in tags.split(separator: ",") {
            let tag = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if !tag.isEmpty, !seen.contains(tag) { seen.append(tag) }
        }
        return seen
    }

    struct StationSaid: Decodable, Sendable {
        var stationuuid: String?
        var name: String?
        var url: String?
        var url_resolved: String?
        var homepage: String?
        var favicon: String?
        var tags: String?
        var country: String?
        var countrycode: String?
        var language: String?
        var codec: String?
        var bitrate: Int?
        var votes: Int?
        var clickcount: Int?
        var hls: Int?
        var lastcheckok: Int?
    }

    private struct FacetSaid: Decodable { let name: String; let stationcount: Int }
    private struct CountrySaid: Decodable {
        let name: String
        let iso_3166_1: String?
        let stationcount: Int
    }
    private struct ServerSaid: Decodable { let name: String }
    private struct ClickSaid: Decodable { let ok: Bool? }
}
