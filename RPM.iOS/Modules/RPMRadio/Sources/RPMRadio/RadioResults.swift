import Foundation
import RPMKit

/// Reduces a directory answer that has several rows for one station to one row per station.
///
/// Matches `RPM.Core/Radio/RadioResults.cs` in the desktop app.
///
/// **What the directory returns.** Radio Browser files a stream, not a station, and anyone may
/// file one. A station therefore arrives as rows in two shapes. One name can have several
/// addresses: a search for "kiss fm" returns the Spanish Kiss FM seven times, at 56k and at
/// 128k. One address can have several names: "NPO 2" and "NPO Radio 2" are the same icecast
/// mount, filed twice. A list is for choosing what to listen to, and seven rows for one station
/// is not a useful choice, so both shapes are folded. See ``onePerStation(_:)``.
///
/// **Which row is kept.** The best-sounding one: a reachable stream ranks above an unreachable
/// one, a stated bitrate above an unstated one, and a higher bitrate above a lower one. **The
/// logo is taken from whichever row has one.** The directory's rows for one station disagree
/// about artwork as often as about bitrate, and the worst stream often carries the only working
/// picture. The kept row is the best stream, and it then receives the best logo, so the station
/// does not have to be either the best sounding or the best looking.
///
/// **A station with no logo is never dropped.** A station without a picture is still a station,
/// and many stations are in that state.
public enum RadioResults {
    /// A genre search's answer with the stations that the admin filed under that genre added.
    /// Matches `RadioResults.WithRetagged` in the desktop app. The `retagged` stations were
    /// fetched by uuid. Each one is added only if the rest of `query` allows it: it must be in
    /// the same country, and its name must contain the searched text (the directory's name, or
    /// the admin's title where the station has one). A station that is already in the answer is
    /// not added twice. The result is ordered by play count, highest first, as the directory
    /// orders its answers, so the fold that follows keeps its usual positions.
    public static func withRetagged(_ answer: [RadioStation], _ retagged: [RadioStation],
                                    _ query: RadioQuery) -> [RadioStation] {
        var present = Set(answer.map { $0.uuid.lowercased() })
        let text = query.name?.trimmingCharacters(in: .whitespaces)
        let country = query.countryCode?.trimmingCharacters(in: .whitespaces)
        let added = retagged
            .filter { present.insert($0.uuid.lowercased()).inserted }
            .filter { station in
                guard let country, !country.isEmpty else { return true }
                return station.countryCode?.caseInsensitiveCompare(country) == .orderedSame
            }
            .filter { station in
                guard let text, !text.isEmpty else { return true }
                return station.name.range(of: text, options: .caseInsensitive) != nil
                    || station.edit?.name?.range(of: text, options: .caseInsensitive) != nil
            }
        guard !added.isEmpty else { return answer }

        var queue = added.sorted { $0.clickCount > $1.clickCount }[...]
        var merged: [RadioStation] = []
        merged.reserveCapacity(answer.count + added.count)
        for row in answer {
            while let first = queue.first, first.clickCount > row.clickCount {
                merged.append(first)
                queue = queue.dropFirst()
            }
            merged.append(row)
        }
        merged.append(contentsOf: queue)
        return merged
    }

    /// The directory's answer with each station appearing once, in the order of its first
    /// appearance. The directory sorts by how often a station is played, and sorting again here
    /// would lose that order.
    ///
    /// Two rows are one station when they have the same value for either key (see
    /// ``nameKeyOf(_:)`` and ``streamKeyOf(_:)``). This is transitive, so the two keys together
    /// join more rows than either does alone. For example, "NPO Radio 2" at MP3 192 and "NPO 2"
    /// at MP3 192 are one address under two names. "NPO Radio 2" also appears at AAC 64 under
    /// the same name, and "NPO 2" appears at AAC 64 as well. Neither key joins all four rows,
    /// but the two keys together do.
    public static func onePerStation(_ stations: [RadioStation]) -> [RadioStation] {
        guard stations.count > 1 else { return stations }

        // The groups are worked out before any row is merged. A merge writes a new name and a
        // new logo onto the kept row, so a key taken from a merged row would not be what the
        // directory sent. Reading all keys first makes the groups depend only on the directory's
        // answer, in any order.
        var parent = Array(0..<stations.count)

        func find(_ row: Int) -> Int {
            var row = row
            while parent[row] != row {
                parent[row] = parent[parent[row]]
                row = parent[row]
            }
            return row
        }

        // The lower row number is the group's root. The group is therefore named by the row that
        // the directory listed first, which is the most listened-to row. Its position in the list
        // is the position kept below.
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            if ra < rb { parent[rb] = ra } else { parent[ra] = rb }
        }

        // A row with no key of that kind is not joined to any group and stays on its own.
        func join(_ index: inout [String: Int], _ key: String, _ row: Int) {
            guard !key.isEmpty else { return }
            if let first = index[key] { union(first, row) } else { index[key] = row }
        }

        var byName: [String: Int] = [:]
        var byStream: [String: Int] = [:]
        for (i, station) in stations.enumerated() {
            join(&byName, nameKeyOf(station), i)
            join(&byStream, streamKeyOf(station), i)
        }

        var at: [Int: Int] = [:]
        var kept: [RadioStation] = []
        kept.reserveCapacity(stations.count)

        for (i, station) in stations.enumerated() {
            let group = find(i)
            if let seen = at[group] {
                kept[seen] = better(kept[seen], station)
                continue
            }

            at[group] = kept.count
            kept.append(station)
        }

        return kept
    }

    /// Merges two rows for the same station into one: the better stream, with the best logo
    /// that exists.
    private static func better(_ kept: RadioStation, _ other: RadioStation) -> RadioStation {
        var winner = rank(other) > rank(kept) ? other : kept

        // Every uuid in the group is kept on the winner. Without this the other rows' ids are lost,
        // and anything that identifies a station by uuid (the hidden list that the API serves)
        // would match only one of the ids that the directory uses for the station. See
        // ``RadioStation/alsoFiledAs``.
        var filed: [String] = []
        for source in [kept, other] {
            for id in source.alsoFiledAs + [source.uuid]
            where id.caseInsensitiveCompare(winner.uuid) != .orderedSame
                && !filed.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                filed.append(id)
            }
        }
        winner.alsoFiledAs = filed

        // Every logo from both rows is kept, not only the winner's own, because the row with a
        // working logo is often the 32k stream. The logos are kept as a list and not reduced to
        // one here: whether an image can be decoded is only known by requesting it from the host,
        // and the URL does not show it. So all logos are kept, best guess first, and the view
        // tries them in order. See ``RadioStation/otherLogos``.
        var logos: [String] = []
        var votes: [String: Int] = [:]

        // The winner is gathered first to set the order only, and its logos are not counted as
        // votes. It is one of the two rows below, so counting it twice would only show that the
        // better stream won. That says nothing about which picture is better.
        gather(winner, counts: false, into: &logos, votes: &votes)
        gather(kept, counts: true, into: &logos, votes: &votes)
        gather(other, counts: true, into: &logos, votes: &votes)

        // There is no logo worth trying, so the winner keeps its own `favicon` value. The view
        // draws the antenna in that case, and the field still holds the directory's answer.
        guard !logos.isEmpty else { return winner }

        // Best guess first, so the usual row draws its logo on the first request and not after
        // two requests that fail. Only the order changes. No logo is dropped, and the view tries
        // the others if the first guess is wrong.
        //
        // The first test is the ranker. It judges one address on its own merits, compared with
        // the winner's own site. This makes a broadcaster's own copy of its logo rank above a
        // third party's mirror of it. See ``RadioLogo/rank(_:homepage:)``.
        //
        // The second test is agreement between rows. It is about the fold, not about one address,
        // so the ranker cannot see it. Sometimes a station's rows name two pictures that the
        // ranker scores the same (for example a wordmark and an unrelated letter, both mirrors on
        // the same host). The picture that more rows name is the better choice. This test comes
        // after the ranker because two contributors who agree are weaker evidence than the
        // broadcaster's own site: they may have copied each other.
        //
        // Votes are counted by picture, not by URL. The same image is often filed at three sizes,
        // and that is not the same as three rows that agree. See ``RadioLogo/samePicture(_:)``.
        //
        // The count can be lower than the true count. The merge works on two rows at a time, so a
        // picture that two rows already agreed on reaches the next merge as one candidate with
        // one vote. A picture only gains votes when another row names it, so a low count never
        // favours the wrong picture. It can only fail to favour the right one.
        if logos.count > 1 {
            // The position is the last sort key, which makes the sort stable: candidates that
            // neither test can separate keep the order that the directory gave them. Swift's
            // `sorted(by:)` is not guaranteed to be stable, so the order is stored in `place`.
            let scored = logos.enumerated().map { place, url in
                (url: url,
                 rank: RadioLogo.rank(url, homepage: winner.homepage),
                 votes: votes[RadioLogo.samePicture(url)] ?? 0,
                 place: place)
            }

            logos = scored.sorted {
                if $0.rank != $1.rank { return $0.rank > $1.rank }
                if $0.votes != $1.votes { return $0.votes > $1.votes }
                return $0.place < $1.place
            }
            .map(\.url)
        }

        winner.favicon = logos[0]
        winner.otherLogos = Array(logos.dropFirst())
        return winner
    }

    /// Every drawable logo address of one row, in the row's own order.
    private static func gather(_ from: RadioStation, counts: Bool,
                               into logos: inout [String], votes: inout [String: Int]) {
        take(from.favicon, counts: counts, into: &logos, votes: &votes)
        for url in from.otherLogos {
            take(url, counts: counts, into: &logos, votes: &votes)
        }
    }

    private static func take(_ url: String?, counts: Bool,
                             into logos: inout [String], votes: inout [String: Int]) {
        guard RadioLogo.isDrawable(url), let url else { return }

        // The vote is counted before the duplicate check, and the duplicate check compares the
        // address. Two rows that name one image at one host in two sizes are one candidate to try
        // and also two rows that agree.
        if counts {
            let picture = RadioLogo.samePicture(url)
            votes[picture, default: 0] += 1
        }

        if !logos.contains(where: { $0.caseInsensitiveCompare(url) == .orderedSame }) {
            logos.append(url)
        }
    }

    /// How good a stream is, as one number, so that two streams can be compared without a chain
    /// of tie-breaks at the call site.
    ///
    /// Reachability ranks above bitrate: the directory's checker could not open some streams,
    /// and a 320k stream that does not open is worse to offer than a 96k stream that does. After
    /// that, a higher bitrate ranks higher. A station that states no bitrate ranks below every
    /// station that states one, so an unknown bitrate loses to "96k". Two streams that both
    /// state no bitrate rank the same.
    private static func rank(_ station: RadioStation) -> Int {
        (station.reachable ? 1_000_000 : 0)
            + (station.bitrateKbps > 0 ? 1_000 + station.bitrateKbps : 0)
    }

    /// The first of the two keys: the folded name, together with the country. See
    /// ``RadioNames/fold(_:_:)``, which removes the stream specification, punctuation, accents
    /// and words such as "radio station" from the name.
    ///
    /// This key joins one station that is listed at several bitrates, which is the usual kind of
    /// duplicate: "NPO Radio 2" at MP3 192, AAC 64 and AAC 32 is three rows and three addresses
    /// under one name. The name is folded and not only trimmed, because one name is often spelled
    /// in several ways: "Qmusic", "Q-Music", "Q music Nederland" and "QMUSIC NEDERLAND" are one
    /// station, and so are "Heart", "Heart FM" and "Heart UK".
    ///
    /// The country is part of the key because a name is only unique inside one country. A search
    /// without a country filter finds a "Radio 1" in a dozen countries, and these are different
    /// stations. Merging them would remove eleven broadcasters from the list.
    private static func nameKeyOf(_ station: RadioStation) -> String {
        let name = RadioNames.fold(station.name, station.countryCode)
        guard !name.isEmpty else { return "" }
        return "\(name)|\(country(station))"
    }

    /// The second key: the stream's address, together with the country. The parts that are not
    /// part of the address are removed: the scheme, a leading "www.", a default port and a
    /// trailing slash.
    ///
    /// **What it finds that the name key does not.** The same stream filed twice under two
    /// names. For example, "NPO 2" and "NPO Radio 2" both use `icecast.omroep.nl/radio2-bb-mp3`.
    /// "3FM", "NPO 3FM" and "NPO 3FM Serious Radio" all use `icecast.omroep.nl/3fm-bb-mp3`. "NPO
    /// Klassiek" and "NPO Radio 4" both use `icecast.omroep.nl/radio4-bb-mp3`. Each key joins
    /// rows that the other cannot join, so both are used.
    ///
    /// **Why it is safe to merge on this key.** Two rows with one address are one stream. The row
    /// that is kept plays the audio that both rows describe. This is a stronger statement than
    /// the name key can make.
    ///
    /// **When it is wrong.** The directory may file an address under the wrong station. For
    /// example, a row for Hot 99.5 Washington can name the address of Z100 New York, and then the
    /// two stations merge. The cost is one station missing from a page. The row that is kept
    /// plays what its address says.
    ///
    /// **The query string is kept.** Several directories put the station's identity in the query
    /// string. For example, `playerservices.streamtheworld.com` is one host for hundreds of
    /// stations, so removing the query string would merge broadcasters that share only a CDN.
    ///
    /// **The country is part of the key**, for the same reason as in the name key: CNN and CNN UK
    /// are filed under one address in two countries, and the app treats them as two stations
    /// everywhere else.
    private static func streamKeyOf(_ station: RadioStation) -> String {
        let trimmed = station.streamUrl.trimmingCharacters(in: .whitespaces)
        guard let parts = URLComponents(string: trimmed),
              let raw = parts.host, !raw.isEmpty
        else { return "" }

        var host = raw.lowercased()
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }

        // The scheme is not part of the key: http and https of one address are one stream, and the
        // directory's rows for a station often disagree about which one is used. A port that the
        // scheme uses by default is removed too, so https://h/p and http://h:80/p are not read as
        // two addresses.
        let scheme = parts.scheme?.lowercased()
        let stated = parts.port
        let implied = stated == nil
            || (scheme == "http" && stated == 80)
            || (scheme == "https" && stated == 443)
        let port = implied ? "" : ":\(stated!)"

        // The percent-encoded forms are used. They are the same as `Uri.AbsolutePath` and
        // `Uri.Query` in the desktop app. Each app folds its own list, and a key that is built
        // differently in the two apps would fold the lists differently.
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }

        let query = parts.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(host)\(port)\(path)\(query)|\(country(station))"
    }

    private static func country(_ station: RadioStation) -> String {
        station.countryCode?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    }
}
