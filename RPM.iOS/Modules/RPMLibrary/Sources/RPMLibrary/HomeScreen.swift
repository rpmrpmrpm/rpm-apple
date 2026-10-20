import Foundation
import RPMKit

/// Which question a row of the home screen is asking. The row's heading says which question
/// it is. A row without a named question would be four rows of records in four orders.
public enum HomeRowKind: Sendable, Hashable {
    case listened
    case suggested
    case taste
    case played
    case added
}

/// One row: its question, and the records that stand in it.
public struct HomeRow: Sendable, Equatable {
    public let kind: HomeRowKind
    public let keys: [String]
}

/// What one entry in the quick selection stands for.
public enum QuickPickKind: Sendable, Hashable {
    /// One song, keyed by its cloud id.
    case song

    case album
    case playlist
    case station

    /// A song radio on one of the songs played most, keyed by the song's cloud id. See
    /// ``QuickPicks/radioSeeds(_:)``.
    case radio
}

public struct QuickPick: Sendable, Equatable {
    public let kind: QuickPickKind
    public let key: String

    public init(kind: QuickPickKind, key: String) {
        self.kind = kind; self.key = key
    }
}

public enum QuickPicks {
    /// How many entries the screen shows.
    public static let count = 16

    /// How many song radios the selection offers at most. The desktop's `QuickPicks.MostRadios`.
    public static let mostRadios = 2

    /// The songs to offer a radio on: the one played most, and the next one by another act,
    /// because two radios on one act are one radio. A song whose tags name no act is never
    /// taken for another such song. The desktop's `QuickPicks.RadioSeeds`.
    ///
    /// - Parameter songs: most played first, each with its act.
    public static func radioSeeds(_ songs: [(id: String, act: String)]) -> [String] {
        var seeds: [String] = []
        var acts: Set<String> = []
        for song in songs {
            if seeds.count == mostRadios { break }
            let act = song.act.trimmingCharacters(in: .whitespaces).lowercased()
            if !act.isEmpty && !acts.insert(act).inserted { continue }
            seeds.append(song.id)
        }
        return seeds
    }

    /// How many entries one panel holds. The panels are columns of this many, read down, as
    /// on the desktop (`QuickPicks.Tall`).
    public static let tall = 4

    /// The selection cut into the panels that it is drawn in. Each panel is filled down, and
    /// then the next panel is filled across.
    ///
    /// **Down before across**, as the desktop's `QuickPicks.InPanels` does. The four most
    /// played go down the first panel, and the next four go in the panel that a swipe
    /// brings in. If the picks were filled across instead, the most played would be spread
    /// over four panels, and three of them would be off the screen.
    ///
    /// Short panels are returned short rather than padded out. A selection with nothing in
    /// it gives no panels.
    public static func inPanels(_ picks: [QuickPick], tall: Int) -> [[QuickPick]] {
        guard tall > 0, !picks.isEmpty else { return [] }

        return stride(from: 0, to: picks.count, by: tall).map {
            Array(picks[$0..<min($0 + tall, picks.count)])
        }
    }
}

/// The home screen, worked out in one place: the gate, the banner, the rows, the lists and
/// the quick selection.
///
/// **Settled once per launch.** The draw decides the banner's card and the two drawn rows. A
/// screen that rearranged itself while somebody was looking at it would be worse than one
/// that never changes. The app passes the draw in once, at launch.
///
/// The view draws what this returns and decides nothing.
public struct HomeScreen: Sendable, Equatable {
    public let gate: FeatureGate
    public let strip: [HomeFeature]
    public let rows: [HomeRow]
    /// The computer's generated lists, by name, in the order that they were given. The phone
    /// cannot cut a list again, so it does not reorder them either.
    public let lists: [String]
    public let quickPicks: [QuickPick]

    public func row(_ kind: HomeRowKind) -> [String] {
        rows.first { $0.kind == kind }?.keys ?? []
    }

    /// - Parameter songs: The songs played most, by cloud id, most played first. See ``HomeSongs``.
    /// - Parameter stations: The stations heard most on any of the listener's devices, by uuid.
    ///   These come from the synced station log (`RadioListens` in RPMRadio). The list is
    ///   empty on a borrowed shelf, and for a listener who has not played the radio. The
    ///   banner and the quick selection skip a source that has nothing in it.
    /// - Parameter radios: The songs to offer a radio on (``QuickPicks/radioSeeds(_:)``). They
    ///   come first in the quick selection, ahead of the deal.
    public static func build(shelf: [HomeAlbum], songs: [String], lists: [String],
                             stations: [String], draw: Int, radios: [String] = []) -> HomeScreen {
        let gate = HomeGate.of(albums: shelf.count)
        let length = HomeShelf.rowLength

        let listened = HomeShelf.listened(shelf, count: length)
        let played = HomeShelf.played(shelf, count: length)
        let added = HomeShelf.added(shelf, count: length)

        // The seeds are what has been played. Where nothing has been played, they are what
        // arrived last. A borrowed shelf carries records and no listening at all. The newest
        // records are a worse answer than a week of listening, and a far better answer than nothing.
        let basis = HomeShelf.basis(listened: listened, added: added)
        let byKey = Dictionary(shelf.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let traits = shelf.map(\.traits)
        let seeds = basis.prefix(HomeShelf.tasteSeeds).compactMap { byKey[$0]?.traits }

        // Exclude everything already on the screen above this row. The recently listened row
        // is directly above this one, and the basis is what that row was built from. This
        // passes the WHOLE basis, as the desktop does. On a shelf with no listening, the basis
        // is the recently added row. Excluding only the seeds would let the rest of that row be
        // offered again on the same screen.
        let suggested = HomeShelf.suggested(
            seeds: seeds, traits: traits, exclude: listened + basis,
            count: length, draw: draw)

        let taste = ListeningTaste.of(shelf)
        let fromTaste = HomeShelf.fromTaste(
            artists: taste.artists, genres: taste.genres, traits: traits,
            played: shelf.filter { $0.plays > 0 }.map(\.key),
            exclude: listened + suggested, count: length, draw: draw)

        let rows = [
            HomeRow(kind: .listened, keys: listened),
            HomeRow(kind: .suggested, keys: suggested),
            HomeRow(kind: .taste, keys: fromTaste),
            HomeRow(kind: .played, keys: played),
            HomeRow(kind: .added, keys: added),
        ].filter { !$0.keys.isEmpty }

        // The banner may hold any record that a ranking plainly chooses, so Most played is
        // varied for the banner. The row keeps its own order. Recently added is not varied.
        // It is an order, not a ranking. The card says "the newest record on the shelf", and
        // the eighth newest record is not that.
        let strip = HomeFeatures.strip(
            continued: Array(listened.prefix(1)),
            added: added,
            lists: lists,
            suggested: suggested,
            played: HomeShelf.varied(played, draw: draw, salt: "played", reach: HomeShelf.bannerReach),
            listened: listened,
            stations: stations,
            isVariousArtists: { ArtistCredit.isVariousArtists(byKey[$0]?.artist) },
            count: HomeFeatures.count)

        return HomeScreen(gate: gate, strip: strip, rows: rows, lists: lists,
                          quickPicks: picks(songs: songs, played: played, lists: lists,
                                            stations: stations, radios: radios))
    }

    /// The quick selection: the things a listener plays most, of whatever kind they are.
    ///
    /// **The kinds are not ranked against each other. That is the whole design.** A song
    /// played fifty times, a record played fifty times and a list started fifty times are
    /// three numbers that mean different things. No weighting between them would be better
    /// than a guess that looks like arithmetic. So each kind is ranked within itself. Then
    /// one entry is dealt from each kind in turn.
    ///
    /// The four kinds are the same ones that the desktop deals, in the same order. See
    /// `QuickPicks.Choose`.
    private static func picks(songs: [String], played: [String], lists: [String],
                              stations: [String], radios: [String]) -> [QuickPick] {
        // The radios first: a suggestion made from the rest, not one more kind competing with it.
        var picks = radios.prefix(QuickPicks.mostRadios).map { QuickPick(kind: .radio, key: $0) }

        let sources: [(kind: QuickPickKind, keys: [String])] = [
            (.song, songs), (.album, played), (.playlist, lists), (.station, stations),
        ]

        var cursor = [Int](repeating: 0, count: sources.count)

        while picks.count < QuickPicks.count {
            var dealtThisRound = false

            for (i, source) in sources.enumerated() where cursor[i] < source.keys.count {
                if picks.count >= QuickPicks.count { break }
                picks.append(QuickPick(kind: source.kind, key: source.keys[cursor[i]]))
                cursor[i] += 1
                dealtThisRound = true
            }

            // Every source has been read to the end. Without this check, the loop would run
            // forever on a collection too small to fill the block. Every new collection is that small.
            if !dealtThisRound { break }
        }

        return picks
    }
}
