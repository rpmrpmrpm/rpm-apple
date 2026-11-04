import Foundation

/// A record as the home screen's rows ask about it: what it is, when it arrived, and what
/// has been played of it on any of the listener's devices.
///
/// This is one type, not the desktop's two (its album facts and its album traits). The phone
/// builds them in one pass over the same listing. A second type would mean a second walk of
/// the library to say the same thing twice.
public struct HomeAlbum: Sendable, Equatable {
    public let key: String
    public let album: String
    public let artist: String
    public let genres: [String]
    public let year: Int

    /// The newest of the record's tracks. A record arrives over the minutes that its files
    /// take to copy in. A record that is still arriving should not sort below one that
    /// finished yesterday.
    public let addedAt: Int64

    /// The record's tracks added up. A record played through counts as many plays as it has
    /// tracks. This is what makes the order show the most listened records, not the most owned.
    public let plays: Int

    /// The most recent of the record's tracks, or zero for a record that nobody has played.
    public let lastPlayedAt: Int64

    public init(key: String, album: String, artist: String, genres: [String], year: Int,
                addedAt: Int64, plays: Int, lastPlayedAt: Int64) {
        self.key = key; self.album = album; self.artist = artist
        self.genres = genres; self.year = year
        self.addedAt = addedAt; self.plays = plays; self.lastPlayedAt = lastPlayedAt
    }

    public var traits: AlbumTraits {
        AlbumTraits(key: key, album: album, artist: artist, genres: genres, year: year)
    }
}

/// An act that the listener actually plays.
public struct PlayedArtist: Sendable, Equatable {
    public let name: String
    public let plays: Int

    public init(name: String, plays: Int) {
        self.name = name; self.plays = plays
    }
}

/// A kind of music the listener plays, and how much of their listening it is.
public struct GenreShare: Sendable, Equatable {
    public let genre: String
    /// From zero to one, over the whole of what they play, not over the few kinds kept.
    public let share: Double

    public init(genre: String, share: Double) {
        self.genre = genre; self.share = share
    }
}

/// The home screen's arithmetic: which records stand in which of its rows, from the shelf
/// and nothing else.
///
/// This is a port of `RPM.Core/Library/HomeShelf.cs`, keyed by album key rather than by
/// folder. It lives here rather than in the view, because a row of records is a question
/// asked of a collection. A test can hold that question still.
///
/// **Nothing in it is a preference.** Every row is derived from facts that the library already
/// keeps. So a listener who has played nothing sees the rows that do not need a history, and
/// none of the rows that do.
public enum HomeShelf {
    /// How many records a row holds. The row scrolls sideways, so this is not the number that
    /// fits on screen. It is how far down each order is worth going before the answer stops
    /// being useful.
    public static let rowLength = 20

    /// How many of the recently played records the suggestions are worked out from. Not one,
    /// because one record gives a mood rather than a taste. Not all of them either, because a
    /// collection played over years averages out to the collection itself.
    public static let tasteSeeds = 5

    /// How far down a ranked row the banner may reach for the card it shows. This is eight.
    /// It is a claim about what the row's heading means. "Most played" is true of the third
    /// most played record, but not of the hundredth.
    public static let bannerReach = 8

    /// How many times a row's worth of similar records is asked for, for each seed. This lets
    /// the row be drawn from a pool, rather than being the pool itself.
    public static let pool = 3

    /// How many of the played acts the taste row leans on.
    public static let leaningArtists = 12

    /// How many kinds of music the taste row leans on. There are fewer than acts, because
    /// there are fewer kinds to begin with. A listener plays hundreds of acts and a handful
    /// of genres.
    public static let leaningGenres = 6

    /// How much an act that the listener plays is worth, compared with a genre that they play.
    /// This is higher on purpose. "You play this band" is a fact about the listener. "You
    /// play jazz" is a fact about a thousand records.
    public static let actLean = 1.6

    /// The share of its score that a record the listener has already played keeps. It is not
    /// zero. A listener with a small collection would otherwise get an empty row. A record
    /// played once, a year ago, is a fair thing to offer again.
    public static let playedShare = 0.3

    /// The row that the taste is read from: what has been played, or, where nothing has been
    /// played, what arrived last.
    ///
    /// A borrowed collection carries records and no listening at all. A first evening with
    /// one's own collection is the same. The newest records are a worse answer than a week of
    /// listening, and a far better one than nothing.
    public static func basis(listened: [String], added: [String]) -> [String] {
        listened.isEmpty ? added : listened
    }

    /// Records with a play behind them, newest listen first. Ties are broken by key, so the
    /// row stays the same across two reads of an unchanged shelf.
    public static func listened(_ shelf: [HomeAlbum], count: Int) -> [String] {
        guard count > 0 else { return [] }

        return shelf
            .filter { $0.lastPlayedAt > 0 }
            .sorted { a, b in
                a.lastPlayedAt == b.lastPlayedAt
                    ? a.key.lowercased() < b.key.lowercased()
                    : a.lastPlayedAt > b.lastPlayedAt
            }
            .prefix(count)
            .map(\.key)
    }

    /// Records with plays behind them, most first. The count is tracks played, not times
    /// through. That is what "most listened" means for a shelf of albums.
    public static func played(_ shelf: [HomeAlbum], count: Int) -> [String] {
        guard count > 0 else { return [] }

        return shelf
            .filter { $0.plays > 0 }
            .sorted { a, b in
                if a.plays != b.plays { return a.plays > b.plays }
                if a.lastPlayedAt != b.lastPlayedAt { return a.lastPlayedAt > b.lastPlayedAt }
                return a.key.lowercased() < b.key.lowercased()
            }
            .prefix(count)
            .map(\.key)
    }

    /// Records, newest on the shelf first, played or not. This is the one row that a
    /// collection opened for the first time can fill.
    public static func added(_ shelf: [HomeAlbum], count: Int) -> [String] {
        guard count > 0 else { return [] }

        return shelf
            .sorted { a, b in
                a.addedAt == b.addedAt
                    ? a.key.lowercased() < b.key.lowercased()
                    : a.addedAt > b.addedAt
            }
            .prefix(count)
            .map(\.key)
    }

    /// The front of a ranked row, in an order that the draw decides. The rest of the row is
    /// left alone.
    ///
    /// **For the banner, and never for the row.** A row headed "Most played" is a ranking. It
    /// has to stay in its own order, or the heading stops being true. The banner shows ONE
    /// record and says which question put it there. So it may show any record that the
    /// question plainly answers. If it used the row's own order, it would show the single most
    /// played record for as long as that record stayed in front. On a collection somebody has
    /// had for years, that is forever.
    public static func varied(_ ranked: [String], draw: Int, salt: String, reach: Int) -> [String] {
        guard reach > 1, ranked.count > 1 else { return ranked }

        let front = min(reach, ranked.count)
        return shuffled(Array(ranked.prefix(front)), draw: draw, salt: salt) + ranked.dropFirst(front)
    }

    /// What to play next, from what has been played lately.
    ///
    /// This uses the same ranking as the album page's row. It is asked once for each recently
    /// played record, and the answers are merged round robin. So the front of the row is one
    /// suggestion from each of the last few records, not the whole of the first seed's
    /// answers. A reader looks at the front of a row. The front should cover the width of
    /// their week.
    ///
    /// The ranking is asked per seed, not of an average of the seeds, because there is no
    /// such thing as an average record. The mean of a jazz record and a grime record is neither.
    public static func suggested(seeds: [AlbumTraits], traits: [AlbumTraits],
                                 exclude: [String], count: Int, draw: Int) -> [String] {
        guard count > 0, !seeds.isEmpty else { return [] }

        var taken = Set(exclude.map { $0.lowercased() })
        let answers = seeds.map { seed in
            shuffled(SimilarAlbums.pick(subject: seed, library: traits, count: count * pool).map(\.key),
                     draw: draw, salt: seed.key)
        }

        var row: [String] = []
        var round = 0
        while row.count < count {
            var addedThisRound = false

            for answer in answers where round < answer.count {
                addedThisRound = true
                if taken.insert(answer[round].lowercased()).inserted {
                    row.append(answer[round])
                    if row.count == count { return row }
                }
            }

            // Every seed is out of suggestions. Without this check the loop never ends, on a
            // shelf too small to fill the row. Every new collection is that small.
            if !addedThisRound { break }
            round += 1
        }

        return row
    }

    /// Records by the acts and in the kinds of music that the listener plays most.
    ///
    /// The other recommendations row is ``suggested(seeds:traits:exclude:count:draw:)``. The
    /// difference is the question, not the arithmetic. That row asks what is LIKE the last few
    /// records played, so it follows the listener from one evening to the next. This row asks
    /// what they are into, from all of their listening, so it barely moves.
    ///
    /// **Unheard records first.** A row of what somebody already plays is the most-played row,
    /// two rows down. A record with plays keeps ``playedShare`` of its score rather than being
    /// removed. So the row still fills on a small collection.
    public static func fromTaste(artists: [PlayedArtist], genres: [GenreShare],
                                 traits: [AlbumTraits], played: [String], exclude: [String],
                                 count: Int, draw: Int) -> [String] {
        guard count > 0, !artists.isEmpty else { return [] }

        // Each act's weight is its share of the plays of the leaned-on acts. So a favourite band
        // outranks the twelfth act the listener has played, rather than tying with it. Each name
        // is folded the same way that the ranking folds a credit, so one act spelled two ways
        // counts as one act.
        let top = Array(artists.prefix(leaningArtists))
        let actPlays = Double(top.reduce(0) { $0 + $1.plays })
        var acts: [String: Double] = [:]
        for act in top {
            let key = SimilarAlbums.fold(act.name)
            guard !key.isEmpty else { continue }
            acts[key] = actPlays > 0 ? Double(act.plays) / actPlays : 1.0 / Double(top.count)
        }

        // The genre shares already add up to one over everything played. They are used as they
        // come, not re-scaled over the few kept. A listener whose top six genres are a third of
        // their listening should not have those six read as their whole taste.
        var kinds: [String: Double] = [:]
        for share in genres.prefix(leaningGenres) {
            kinds[share.genre.lowercased()] = share.share
        }

        let skip = Set(exclude.map { $0.lowercased() })
        let heard = Set(played.map { $0.lowercased() })

        var scored: [(key: String, score: Double)] = []
        for album in traits {
            if skip.contains(album.key.lowercased()) { continue }

            var score = (acts[SimilarAlbums.fold(album.artist)] ?? 0) * actLean
            for genre in album.genres {
                score += kinds[genre.lowercased()] ?? 0
            }

            // Neither their act nor their kind of music: not an answer to this question.
            if score <= 0 { continue }

            scored.append((album.key,
                           heard.contains(album.key.lowercased()) ? score * playedShare : score))
        }

        scored.sort { a, b in
            a.score == b.score ? a.key.lowercased() < b.key.lowercased() : a.score > b.score
        }

        // One salt for the whole row, not one per seed. This row has no seeds. It is one ranking
        // over the shelf. The salt is a constant, so the draw alone decides the shuffle.
        return Array(shuffled(scored.prefix(count * pool).map(\.key), draw: draw, salt: "taste")
            .prefix(count))
    }

    /// One pool, shuffled by the draw and by a salt that the caller chooses.
    ///
    /// The result is deterministic for both inputs. Two seeds drawing on the same launch must
    /// not walk the same shuffle. Otherwise a round-robin row would take the same positions
    /// from each. No system random generator is used, because the answer has to be the same
    /// in every process for a given draw.
    private static func shuffled(_ keys: [String], draw: Int, salt: String) -> [String] {
        var state = Int32(truncatingIfNeeded: draw)
        for scalar in salt.unicodeScalars {
            state = state &* 31 &+ Int32(truncatingIfNeeded: scalar.value)
        }
        state = state &* Int32(bitPattern: 2_654_435_761)

        var out = keys
        var i = out.count - 1
        while i > 0 {
            state = state &* 1_103_515_245 &+ 12345
            let j = Int(UInt32(bitPattern: state >> 8) % UInt32(i + 1))
            out.swapAt(i, j)
            i -= 1
        }

        return out
    }
}
