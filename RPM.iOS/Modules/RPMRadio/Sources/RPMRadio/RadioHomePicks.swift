import Foundation

/// Why a station stands on the radio home: the person pinned it, saved it, heard it often, it is
/// local, or it is suggested.
public enum StationWhy: Sendable, Equatable {
    case pinned, saved, heard, local, forYou
}

/// One station on the radio home, with the reason it is there.
public struct StationPick: Sendable, Equatable, Identifiable {
    public let station: RadioStation
    public let why: StationWhy

    public var id: String { station.uuid }

    public init(station: RadioStation, why: StationWhy) {
        self.station = station
        self.why = why
    }
}

/// What the phone's radio home shows, worked out from the lists it already has. There is no
/// network here: the lists come from the directory (the local stations, the world's most played
/// stations, a genre's stations), from ``RadioListens`` (the stations heard most), from the saved
/// stations and from the stations the person pinned.
///
/// A station is listed once on each part of the page. Two entries count as the same station when
/// one's uuid is the other's, or is one of the entries folded into it
/// (``RadioStation/alsoFiledAs``).
///
/// The same rules are in the Android app's `RadioHomePicks.kt`. Change both files together.
public enum RadioHomePicks {
    /// The most cards on the banner.
    public static let bannerMost = 6

    /// The most lines on the quick selection: four panels of four, as on home.
    public static let quickMost = 16

    /// How many lines one panel of the quick selection holds, read down, as on home.
    public static let tall = 4

    /// The most suggested stations on the quick selection. They come after the pinned and the
    /// saved stations.
    public static let suggestedMost = 8

    /// How many of the stations heard most are read for the person's taste.
    public static let tasteFrom = 20

    /// How many genres the suggestions are asked for.
    public static let tasteGenres = 2

    /// The banner: the stations heard most and the local stations, one of each in turn, heard
    /// first. When one list runs out, the other fills the banner.
    ///
    /// The stations that are `dressed` come first, from anywhere in either list, in that same
    /// order; the others follow in that order. The radio home passes the stations with both a card
    /// picture and a description from the admin, because their cards are the best looking ones.
    public static func banner(heard: [RadioStation], local: [RadioStation],
                              most: Int = bannerMost,
                              dressed: (RadioStation) -> Bool = { _ in false }) -> [StationPick] {
        var picks = Picks(most: .max)
        for at in 0..<max(heard.count, local.count) {
            if at < heard.count { picks.add(heard[at], .heard) }
            if at < local.count { picks.add(local[at], .local) }
        }
        let first = picks.list.filter { dressed($0.station) }
        let rest = picks.list.filter { !dressed($0.station) }
        return Array((first + rest).prefix(max(0, most)))
    }

    /// The quick selection: what the person pinned, in the order they pinned it, then their saved
    /// stations, then the suggestions.
    public static func quick(pinned: [RadioStation], saved: [RadioStation],
                             suggested: [RadioStation], most: Int = quickMost) -> [StationPick] {
        var picks = Picks(most: most)
        for station in pinned { picks.add(station, .pinned) }
        for station in saved { picks.add(station, .saved) }
        for station in suggested { picks.add(station, .forYou) }
        return picks.list
    }

    /// The genres that `stations` play most, most first, at most `most`. Each station counts once
    /// for each genre its tags name (``RadioGenres/names(_:)``).
    ///
    /// Two genres with the same count keep the order in which they were first met, so the stations
    /// given first decide: pass the pinned and saved stations before the ones heard.
    public static func taste(_ stations: [RadioStation], most: Int = tasteGenres) -> [String] {
        var counts: [String: Int] = [:]
        var met: [String] = []
        for station in stations {
            var named = Set<String>()
            for genre in station.shownTags.flatMap({ RadioGenres.names($0) }) {
                guard named.insert(genre).inserted else { continue }
                if counts[genre] == nil { met.append(genre) }
                counts[genre, default: 0] += 1
            }
        }
        // Sorted by count, and by first meeting within one count. The order is stated in full
        // because the standard sort does not promise to keep the order of equal elements.
        let ranked = met.enumerated().sorted { one, other in
            let a = counts[one.element] ?? 0, b = counts[other.element] ?? 0
            return a != b ? a > b : one.offset < other.offset
        }
        return ranked.prefix(max(0, most)).map(\.element)
    }

    /// Suggestions from `answers`, one list for each genre of the person's taste: one station from
    /// each list in turn, leaving out the stations in `known` (those already pinned, saved or
    /// heard), at most `most`.
    public static func suggested(_ answers: [[RadioStation]], known: [RadioStation],
                                 most: Int = suggestedMost) -> [RadioStation] {
        var seen = Seen()
        for station in known { _ = seen.add(station) }
        var out: [RadioStation] = []
        guard most > 0 else { return out }
        let longest = answers.map(\.count).max() ?? 0
        for at in 0..<longest {
            for answer in answers where at < answer.count {
                let station = answer[at]
                if seen.add(station) { out.append(station) }
                if out.count >= most { return out }
            }
        }
        return out
    }

    /// The stations of `stations` that are not in `without`, each once.
    public static func without(_ stations: [RadioStation], _ without: [RadioStation]) -> [RadioStation] {
        var seen = Seen()
        for station in without { _ = seen.add(station) }
        return stations.filter { seen.add($0) }
    }

    /// The quick selection cut into the panels it is drawn in: each panel filled down, then the
    /// next panel across, as home's quick selection is. A last panel that is short is returned
    /// short. An empty selection gives no panels.
    public static func inPanels(_ picks: [StationPick], tall: Int = tall) -> [[StationPick]] {
        guard tall > 0, !picks.isEmpty else { return [] }
        return stride(from: 0, to: picks.count, by: tall).map {
            Array(picks[$0..<min($0 + tall, picks.count)])
        }
    }

    /// The ids already taken: each station by its uuid and the uuids folded into it, all in lower
    /// case.
    private struct Seen {
        private var ids = Set<String>()

        /// Takes `station` and returns true, or returns false when it is a station already taken.
        mutating func add(_ station: RadioStation) -> Bool {
            let all = ([station.uuid] + station.alsoFiledAs).map { $0.lowercased() }
            if all.contains(where: { ids.contains($0) }) { return false }
            ids.formUnion(all)
            return true
        }
    }

    /// A list of picks with no station twice, at most `most` long.
    private struct Picks {
        let most: Int
        private var seen = Seen()
        private(set) var list: [StationPick] = []

        init(most: Int) { self.most = most }

        var full: Bool { list.count >= most }

        mutating func add(_ station: RadioStation, _ why: StationWhy) {
            guard !full, seen.add(station) else { return }
            list.append(StationPick(station: station, why: why))
        }
    }
}
