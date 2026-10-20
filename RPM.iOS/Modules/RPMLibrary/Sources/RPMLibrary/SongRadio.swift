import Foundation
import RPMKit

/// One song a radio can play or start from.
///
/// `record` is the album's key: a radio spaces records by it. `song` is the act and the
/// title with the edition notes taken off, lower cased: two tracks with the same value are
/// one song on two records. `genre` is the shelf the record is filed on, `styles` the
/// styles its tags name, `moods` the moods the computer put it in.
public struct RadioSong: Sendable, Equatable {
    public let id: String
    public let record: String
    public let artist: String
    public let song: String
    public let year: Int
    public let genre: String?
    public let styles: Set<String>
    public let moods: Set<String>
    public let offered: Bool
    public let plays: Int

    public init(id: String, record: String, artist: String, song: String, year: Int, genre: String?,
                styles: Set<String>, moods: Set<String>, offered: Bool, plays: Int) {
        self.id = id; self.record = record; self.artist = artist; self.song = song; self.year = year
        self.genre = genre; self.styles = styles; self.moods = moods; self.offered = offered; self.plays = plays
    }
}

/// Every song in one collection that a radio can pick from or start from. Built once when a
/// radio starts and held by it, so picking reads nothing.
public struct RadioCrate: Sendable {
    /// How many plays make a favourite. Once or twice is a song that was tried.
    public static let favouriteLeastPlays = 3

    /// How many of the most played songs count as favourites.
    public static let favouritePool = 150

    /// A track shorter than this is an interlude: it can start a radio but is never picked.
    /// The desktop's `Moods.LeastSeconds`.
    public static let leastSeconds = 60.0

    public let songs: [RadioSong]
    private let byId: [String: RadioSong]
    private let favourites: Set<String>

    public init(_ songs: [RadioSong]) {
        self.songs = songs
        self.byId = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let loved = songs
            .filter { $0.offered && $0.plays >= Self.favouriteLeastPlays }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.id < $1.id }
            .prefix(Self.favouritePool)
        self.favourites = Set(loved.map(\.id))
    }

    public func find(_ id: String) -> RadioSong? { byId[id] }

    /// Whether the song is one of the ``favouritePool`` the listener plays most.
    public func isFavourite(_ song: RadioSong) -> Bool { favourites.contains(song.id) }

    /// The crate for a collection. A record's shelf is the one most of its tracks' tags
    /// name, as the desktop files a record by its majority, so one oddly tagged track does
    /// not move it.
    ///
    /// - Parameters:
    ///   - played: what has been played, by rpmId (`PlayLog.everythingPlayed`).
    ///   - moods: the moods each track is in, by rpmId (``SongRadio/moods(in:)``).
    public static func of(_ albums: [CloudAlbum], played: [String: PlayLog.Played],
                          moods: [String: Set<String>]) -> RadioCrate {
        var stylesOf: [String: Set<String>] = [:]
        var songs: [RadioSong] = []
        for album in albums {
            var counts: [String: Int] = [:]
            for track in album.tracks {
                if let shelf = Genres.match(track.tags?.genre) { counts[shelf, default: 0] += 1 }
            }
            let shelf = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
            for track in album.tracks {
                let tag = track.tags?.genre
                var styles: Set<String> = []
                if let tag {
                    if let known = stylesOf[tag] { styles = known } else {
                        styles = Genres.styles(tag)
                        stylesOf[tag] = styles
                    }
                }
                let albumArtist = track.tags?.albumArtist?.trimmingCharacters(in: .whitespaces) ?? ""
                songs.append(RadioSong(
                    id: track.rpmId,
                    record: album.key,
                    artist: albumArtist.isEmpty ? (track.artist ?? "").trimmingCharacters(in: .whitespaces) : albumArtist,
                    song: songOf(track),
                    year: track.tags?.year ?? 0,
                    genre: shelf ?? Genres.match(tag),
                    styles: styles,
                    moods: moods[track.rpmId] ?? [],
                    offered: (track.tags?.durationSeconds ?? 0) >= leastSeconds,
                    plays: played[track.rpmId]?.plays ?? 0))
            }
        }
        return RadioCrate(songs)
    }

    /// The words inside brackets that mark a note about the recording, not the song.
    private static let asideWords: Set<String> = [
        "remaster", "remastered", "live", "edit", "version", "mix", "mono", "stereo", "deluxe",
        "bonus", "demo", "feat", "ft", "featuring", "with",
    ]

    /// The value two copies of one song share. An untitled track keeps its own id, so it is
    /// never taken for another untitled one.
    static func songOf(_ track: CloudTrack) -> String {
        var title = ""
        var aside = ""
        var depth = 0
        for c in track.title ?? "" {
            if c == "(" || c == "[" {
                depth += 1
                if depth == 1 { aside = ""; continue }
            }
            if (c == ")" || c == "]") && depth > 0 {
                depth -= 1
                if depth == 0 {
                    let words = aside.lowercased().split(whereSeparator: { !$0.isLetter })
                    let isNote = words.contains { word in
                        asideWords.contains(String(word)) || word.hasPrefix("remaster")
                    }
                    if !isNote { title += "(\(aside))" }
                    continue
                }
            }
            if depth > 0 { aside.append(c) } else { title.append(c) }
        }
        let name = title.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return track.rpmId }
        return (track.artist ?? "").trimmingCharacters(in: .whitespaces).lowercased() + "\n" + name
    }
}

/// Picks the songs a song radio plays next, as the desktop's `SongRadio` does: songs close
/// to the one playing in mood, era and genre, down to the style (trip hop is not electro),
/// with the song the radio started from counting for half as much again so a long session
/// does not drift. Every ``favouriteEvery``th song is one the listener plays most, when one
/// fits as well as the closest few percent of the collection; one that does not fit is not
/// forced in.
///
/// The phone has less to go on than the computer. It has no mood readings and no tempo, only
/// which of the computer's mood lists a song is in, and no styles but the ones a song's own
/// genre tag names. So the mood term is the lists alone, and tempo is not asked. The Android
/// apps' `SongRadio` is the same; change both together.
///
/// Pure: the crate, the queue and the history are handed in, and the answer is a list of
/// rpmIds.
public enum SongRadio {
    /// How many songs a radio keeps queued after the one playing.
    public static let ahead = 10

    /// Every this many songs the radio queues, one is a favourite where one fits. Counted
    /// from the song the radio started from.
    public static let favouriteEvery = 5

    static let originWeight = 0.5
    static let shortlist = 6
    static let artistGap = 5
    static let recordGap = 12
    static let eraSpan = 15.0

    /// What a term gives when either song lacks the fact it compares: halfway, so an unknown
    /// is never taken for a match.
    static let unknown = 0.5
    static let relatedGenre = 0.5
    static let kinStyle = 0.3
    static let otherStyle = 0.6
    static let oneStyle = 0.15

    /// The mood term when one song is in a mood list and the other in none.
    static let oneInAMood = 0.75

    /// How close a favourite must be: among this share of what the radio could play now,
    /// never fewer than a shortlist.
    static let favouriteFit = 0.05

    /// The kinds of list that are a mood, as the desktop's `MoodShelf.MoodsByPath` counts them.
    static let moodKinds: Set<String> = ["Calm", "Energetic", "Danceable", "Focus", "Sleep"]

    /// Styles that sit next to one another. The desktop's `SongRadio.StyleFamilies`; change
    /// both together.
    static let styleFamilies: [[String]] = [
        ["Downtempo", "Trip Hop", "Chillout", "Chillwave", "Lo-fi Beats", "Ambient", "New Age", "Folktronica",
         "Vaporwave", "Ambient Techno", "Ambient Classical"],
        ["IDM", "Leftfield", "Electronica", "Progressive Electronic", "Downtempo", "Trip Hop"],
        ["Electro", "Electro House", "Trance", "Psytrance", "Eurodance", "Italo Dance", "Hardstyle", "Future Bass",
         "Alternative Dance", "Deep House", "Tech House", "Progressive House", "Future House", "French House",
         "Garage House", "Tribal House", "Acid House", "Chicago House", "Afro House", "Euro House",
         "Detroit Techno", "Minimal Techno", "Acid Techno", "Hard Techno", "Industrial Techno"],
        ["Drum and Bass", "Jungle", "Breakbeat", "Dubstep", "Post-Dubstep", "UK Garage", "Speed Garage", "Future Bass"],
        ["Synthwave", "Dark Wave", "Ethereal Wave", "Minimal Wave", "Witch House", "Industrial", "Post-Industrial",
         "Dark Ambient"],
        ["Medieval", "Renaissance", "Early Music", "Baroque"],
        ["Baroque", "Classical Period"],
        ["Classical Period", "Romantic Classical"],
        ["Romantic Classical", "Impressionist"],
        ["Impressionist", "Contemporary Classical", "Modern Classical", "Minimalism", "Post-Minimalism",
         "Ambient Classical"],
    ]

    private static let familiesOf: [String: Set<Int>] = {
        var map: [String: Set<Int>] = [:]
        for (at, family) in styleFamilies.enumerated() {
            for style in family { map[style.lowercased(), default: []].insert(at) }
        }
        return map
    }()

    /// A classical record's year is when it was recorded, not when the music is from, so two
    /// of them are not compared by era.
    private static let classical: Set<String> = ["classical", "neo-classical", "opera"]

    /// Which of the plain moods each track is in, by rpmId: every window of every list of
    /// those kinds, a genre's cut of a mood included. Decades are not moods.
    public static func moods(in cut: CloudMoodLists?) -> [String: Set<String>] {
        var byId: [String: Set<String>] = [:]
        for list in cut?.lists ?? [] where moodKinds.contains(list.kind) && list.decade == 0 {
            for id in list.trackIds { byId[id, default: []].insert(list.kind) }
        }
        return byId
    }

    /// The next songs, in the order they should be queued.
    ///
    /// - Parameters:
    ///   - seed: the song playing.
    ///   - origin: the song the radio started from.
    ///   - inQueue: every song queued now.
    ///   - history: every song this radio has queued, oldest first, the origin included.
    /// - Returns: at most `count` rpmIds. Empty when neither the seed nor the origin is in
    ///   the crate.
    public static func pick<R: RandomNumberGenerator>(
        _ crate: RadioCrate, seed: String, origin: String, inQueue: Set<String>,
        history: [String], count: Int, using random: inout R
    ) -> [String] {
        guard count > 0, let playing = crate.find(seed) ?? crate.find(origin) else { return [] }
        let start = crate.find(origin) ?? playing

        var ranked = rankedSongs(crate, playing: playing, origin: start,
                                 blocked: blocked(crate, inQueue, history, seed, origin))
        if ranked.count < count && history.count > 1 {
            // Nearly everything has been queued: the older half of the history may come back.
            ranked = rankedSongs(crate, playing: playing, origin: start,
                                 blocked: blocked(crate, inQueue, Array(history.dropFirst(history.count / 2)), seed, origin))
        }

        var recent = history.suffix(recordGap).compactMap(crate.find)
        recent.append(playing)

        var picked: [String] = []
        var takenIds: Set<String> = []
        var takenSongs: Set<String> = []
        let fitDepth = min(ranked.count, max(shortlist, Int((Double(ranked.count) * favouriteFit).rounded(.up))))

        func free(_ song: RadioSong) -> Bool { !takenIds.contains(song.id) && !takenSongs.contains(song.song) }

        while picked.count < count {
            var list: [RadioSong] = []
            let slot = history.count + picked.count
            if slot > 0 && slot % favouriteEvery == 0 {
                for song in ranked.prefix(fitDepth) where crate.isFavourite(song) && free(song) && spaced(song, recent) {
                    list.append(song)
                    if list.count == shortlist { break }
                }
            }
            if list.isEmpty { list = Array(ranked.lazy.filter { free($0) && spaced($0, recent) }.prefix(shortlist)) }
            // Nothing passes the spacing rules: spacing gives way rather than the radio going quiet.
            if list.isEmpty { list = Array(ranked.lazy.filter { free($0) }.prefix(shortlist)) }
            guard !list.isEmpty else { break }

            let pick = list[Int.random(in: 0..<list.count, using: &random)]
            picked.append(pick.id)
            takenIds.insert(pick.id)
            takenSongs.insert(pick.song)
            recent.append(pick)
        }
        return picked
    }

    /// How far apart two songs are in mood, era and genre, from 0 to 1.
    static func apart(_ song: RadioSong, _ to: RadioSong) -> Double {
        apart(song, to, related: relatedTo(to.genre))
    }

    private static func apart(_ song: RadioSong, _ to: RadioSong, related: Set<String>) -> Double {
        (moodApart(song, to) + eraApart(song, to) + genreApart(song, to, related: related)) / 3
    }

    static func moodApart(_ a: RadioSong, _ b: RadioSong) -> Double {
        if a.moods.isEmpty && b.moods.isEmpty { return unknown }
        if a.moods.isEmpty || b.moods.isEmpty { return oneInAMood }
        return a.moods.isDisjoint(with: b.moods) ? 1 : 0
    }

    static func eraApart(_ a: RadioSong, _ b: RadioSong) -> Double {
        if let x = a.genre?.lowercased(), let y = b.genre?.lowercased(),
           classical.contains(x), classical.contains(y) { return 0 }
        guard a.year > 0, b.year > 0 else { return unknown }
        return min(Double(abs(a.year - b.year)) / eraSpan, 1)
    }

    /// The shelves first, then the styles within them. See the desktop's `SongRadio.GenreApart`.
    static func genreApart(_ song: RadioSong, _ to: RadioSong) -> Double {
        genreApart(song, to, related: relatedTo(to.genre))
    }

    private static func genreApart(_ song: RadioSong, _ to: RadioSong, related: Set<String>) -> Double {
        let styles = styleApart(song.styles, to.styles)
        guard let genre = song.genre, let other = to.genre else {
            if let styles, styles <= kinStyle { return styles }
            return unknown
        }
        if genre.caseInsensitiveCompare(other) == .orderedSame {
            if let styles { return styles }
            return song.styles.isEmpty && to.styles.isEmpty ? 0 : oneStyle
        }
        let shelves = related.contains(genre.lowercased()) ? relatedGenre : 1
        if let styles, styles <= kinStyle { return min(shelves, styles) }
        return shelves
    }

    /// 0 for a style in common, ``kinStyle`` for kin, ``otherStyle`` for neither, nil when
    /// either has none.
    static func styleApart(_ a: Set<String>, _ b: Set<String>) -> Double? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        let lowerB = Set(b.map { $0.lowercased() })
        if a.contains(where: { lowerB.contains($0.lowercased()) }) { return 0 }
        for x in a {
            guard let ofX = familiesOf[x.lowercased()] else { continue }
            for y in b where !(familiesOf[y.lowercased()]?.isDisjoint(with: ofX) ?? true) { return kinStyle }
        }
        return otherStyle
    }

    private static func relatedTo(_ genre: String?) -> Set<String> {
        guard let genre else { return [] }
        return Set(Genres.related(genre).map { $0.lowercased() })
    }

    /// Whether the act and the record have been away long enough. An empty credit names nobody.
    private static func spaced(_ song: RadioSong, _ recent: [RadioSong]) -> Bool {
        var i = recent.count - 1
        while i >= 0 && i >= recent.count - recordGap {
            let other = recent[i]
            if other.record == song.record { return false }
            if i >= recent.count - artistGap, !song.artist.isEmpty,
               other.artist.caseInsensitiveCompare(song.artist) == .orderedSame { return false }
            i -= 1
        }
        return true
    }

    private static func blocked(_ crate: RadioCrate, _ inQueue: Set<String>, _ history: [String],
                                _ seed: String, _ origin: String) -> (ids: Set<String>, songs: Set<String>) {
        var ids = inQueue
        ids.formUnion(history)
        ids.insert(seed)
        ids.insert(origin)
        return (ids, Set(ids.compactMap { crate.find($0)?.song }))
    }

    /// Every song that may be picked, closest first, the id breaking a tie so one crate always
    /// ranks the same way. The related shelves are worked out once per pick.
    private static func rankedSongs(_ crate: RadioCrate, playing: RadioSong, origin: RadioSong,
                                    blocked: (ids: Set<String>, songs: Set<String>)) -> [RadioSong] {
        let playingRelated = relatedTo(playing.genre)
        let originRelated = relatedTo(origin.genre)
        return crate.songs
            .filter { $0.offered && !blocked.ids.contains($0.id) && !blocked.songs.contains($0.song) }
            .map { song in
                (song, apart(song, playing, related: playingRelated) + originWeight * apart(song, origin, related: originRelated))
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }
            .map(\.0)
    }
}
