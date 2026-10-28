import Foundation
import RPMKit

/// One song a radio can play or start from.
///
/// `record` is the album's key: a radio spaces records by it. `song` is the act and the
/// title with the edition notes taken off, lower cased: two tracks with the same value are
/// one song on two records. `genre` is the shelf the record is filed on, `styles` the
/// styles its tags name, `moods` the moods the computer put it in. `live` is whether it is a
/// live recording (``SongRadio/isLive(title:album:releaseType:)``).
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
    public let live: Bool

    public init(id: String, record: String, artist: String, song: String, year: Int, genre: String?,
                styles: Set<String>, moods: Set<String>, offered: Bool, plays: Int, live: Bool = false) {
        self.id = id; self.record = record; self.artist = artist; self.song = song; self.year = year
        self.genre = genre; self.styles = styles; self.moods = moods; self.offered = offered; self.plays = plays
        self.live = live
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
                    plays: played[track.rpmId]?.plays ?? 0,
                    live: SongRadio.isLive(title: track.title, album: track.album ?? album.album,
                                           releaseType: track.tags?.releaseType)))
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
    /// As far as kin: a matching style comes clearly before one nobody has filed.
    static let oneStyle = kinStyle

    /// How many songs must be left, beyond the ones a pick asks for, before songs whose style
    /// clashes with the song playing are left out.
    static let clashSpare = shortlist

    /// What a live recording adds to its score when the radio did not start from a live song:
    /// about a decade of era. A live song still comes when nothing in the studio is near. The
    /// desktop's `LiveApart`.
    static let liveApart = 0.3

    /// The mood term when one song is in a mood list and the other in none.
    static let oneInAMood = 0.75

    /// How close a favourite must be: among this share of what the radio could play now,
    /// never fewer than a shortlist.
    static let favouriteFit = 0.05

    /// The kinds of list that are a mood, as the desktop's `MoodShelf.MoodsByPath` counts them.
    static let moodKinds: Set<String> = ["Calm", "Energetic", "Danceable", "Focus", "Sleep"]

    /// Styles that sit next to one another. The desktop's `SongRadio.StyleFamilies`; change
    /// both together. Every shelf has its families, because two styles that share none clash,
    /// and a song whose style clashes with the one playing is left out (``withoutClashes(_:playing:count:)``).
    static let styleFamilies: [[String]] = [
        // Electronic music for sitting down.
        ["Downtempo", "Trip Hop", "Chillout", "Chillwave", "Lo-fi Beats", "Ambient", "New Age", "Folktronica",
         "Vaporwave", "Ambient Techno", "Ambient Classical"],
        // For listening rather than dancing, but not to sleep to.
        ["IDM", "Leftfield", "Electronica", "Progressive Electronic", "Downtempo", "Trip Hop"],
        // For a club.
        ["Electro", "Electro House", "Trance", "Psytrance", "Eurodance", "Italo Dance", "Hardstyle", "Future Bass",
         "Alternative Dance", "Deep House", "Tech House", "Progressive House", "Future House", "French House",
         "Garage House", "Tribal House", "Acid House", "Chicago House", "Afro House", "Euro House",
         "Detroit Techno", "Minimal Techno", "Acid Techno", "Hard Techno", "Industrial Techno"],
        // Breaks and bass.
        ["Drum and Bass", "Jungle", "Breakbeat", "Dubstep", "Post-Dubstep", "UK Garage", "Speed Garage", "Future Bass"],
        // The dark end.
        ["Synthwave", "Dark Wave", "Ethereal Wave", "Minimal Wave", "Witch House", "Industrial", "Post-Industrial",
         "Dark Ambient"],
        // Pop for dancing, and the dance music it shares a floor with.
        ["Dance-Pop", "Electropop", "Europop", "Synth-Pop", "Teen Pop", "Bubblegum Pop", "Hyperpop", "K-Pop", "J-Pop",
         "Eurodance", "Italo Dance", "Hi-NRG", "Italo-Disco"],
        // Pop to sit back to.
        ["Ballad", "Easy Listening", "Adult Contemporary", "Traditional Pop", "Sophisti-Pop", "Soft Rock",
         "Chanson Française"],
        // Pop for listening closely.
        ["Art Pop", "Progressive Pop", "Psychedelic Pop", "Baroque Pop", "Alternative Pop", "Sophisti-Pop"],
        // ── Rock ──
        // Classic and hard rock: big riffs, big choruses.
        ["Classic Rock", "Hard Rock", "Arena Rock", "AOR", "Blues Rock", "Southern Rock", "Glam Rock", "Heartland Rock",
         "Pub Rock", "Roots Rock", "Glam Metal", "Heavy Metal",
         // Folk sits beside it: the same records, the same years, often the same players.
         "Folk Rock", "Contemporary Folk", "Folk Pop", "Folk Revival", "Traditional Folk", "Alternative Folk",
         "Indie Folk", "Singer-Songwriter"],
        // Soft, acoustic and rootsy.
        ["Soft Rock", "Acoustic Rock", "Folk Rock", "Country Rock", "Piano Rock", "Singer-Songwriter", "Heartland Rock",
         "Roots Rock", "AOR", "Americana", "Folk Pop", "Contemporary Folk", "Folk Revival", "Traditional Folk",
         "Celtic Folk", "Alternative Folk", "Indie Folk"],
        // Rock with a pop song in it.
        ["Pop Rock", "Power Pop", "Soft Rock", "Piano Rock", "AOR", "Britpop", "Jangle Pop", "Indie Pop", "Pop Punk"],
        // Alternative and grunge.
        ["Alternative Rock", "Grunge", "Post-Grunge", "Indie Rock", "Britpop", "Garage Rock Revival", "Noise Rock",
         "Alternative Metal", "Shoegaze", "Post-Punk Revival", "Emo", "Alternative Punk"],
        // Progressive, psychedelic and art rock.
        ["Progressive Rock", "Psychedelic Rock", "Art Rock", "Space Rock", "Krautrock", "Experimental Rock", "Post-Rock",
         "Symphonic Rock", "Acid Rock", "Neo-Psychedelia", "Progressive Metal", "Avant-Prog", "Art Pop",
         "Progressive Pop"],
        // The eighties' new wave, with its synthesisers.
        ["New Wave", "New Romantic", "Synth-Pop", "Post-Punk", "Gothic Rock", "Dance-Rock", "Dark Wave", "Minimal Wave",
         "Sophisti-Pop"],
        // Rock and roll and the garage it grew up in.
        ["Rock and Roll", "Rockabilly", "Surf Rock", "Merseybeat", "Garage Rock", "Doo-Wop", "Proto-Punk"],
        // Heavy, with machines or a rapper in it.
        ["Industrial Rock", "Industrial Metal", "Nu Metal", "Rap Rock", "Alternative Metal", "Industrial", "Electropunk",
         "Funk Rock"],

        // ── Metal ──
        ["Heavy Metal", "Glam Metal", "Power Metal", "Speed Metal", "Thrash Metal", "Pop Metal", "Symphonic Metal",
         "Gothic Metal", "Folk Metal"],
        ["Death Metal", "Black Metal", "Deathcore", "Metalcore", "Thrash Metal", "Speed Metal", "Djent"],
        ["Doom Metal", "Sludge Metal", "Post-Metal", "Drone", "Post-Rock"],
        ["Nu Metal", "Alternative Metal", "Industrial Metal", "Rap Rock", "Metalcore", "Post-Grunge", "Djent"],

        // ── Punk ──
        ["Punk Rock", "Pop Punk", "Skate Punk", "Ska Punk", "Street Punk", "Hardcore Punk", "Garage Punk", "Proto-Punk",
         "Riot Grrrl", "Crust Punk", "Powerviolence"],
        ["Post-Punk", "Post-Hardcore", "Emo", "Screamo", "Alternative Punk"],
        ["Folk Punk", "Anti-Folk"],

        // ── Indie ──
        ["Indie Pop", "Bedroom Pop", "Dream Pop", "Jangle Pop", "Chamber Pop", "Lo-fi", "Indie Folk", "Indietronica",
         "Alternative Pop"],
        ["Indie Rock", "Shoegaze", "Slowcore", "Neo-Psychedelia", "Post-Punk Revival", "Garage Rock Revival", "Lo-fi",
         "Dream Pop"],

        // ── Hip-hop and rap ──
        // Thoughtful, sampled, jazzy.
        ["Conscious Hip Hop", "Alternative Hip Hop", "Jazz Rap", "Political Hip Hop", "Boom Bap", "Golden Age Hip Hop",
         "East Coast Hip Hop", "Turntablism", "Experimental Hip Hop", "Contemporary R&B"],
        // Hard, from the streets of one coast or another.
        ["Hardcore Hip Hop", "Gangsta Rap", "East Coast Hip Hop", "West Coast Hip Hop", "G-Funk", "Southern Hip Hop",
         "Crunk", "Drill", "Grime"],
        // Melodic, sung half the time, on trap drums.
        ["Pop Rap", "Cloud Rap", "Emo Rap", "Trap Soul", "Plugg", "Rage", "Phonk", "Southern Hip Hop", "Trap Latino"],
        ["Experimental Hip Hop", "Industrial Hip Hop", "Alternative Hip Hop", "Cloud Rap"],
        ["Miami Bass", "Crunk", "Jersey Club"],

        // ── R&B, soul and funk ──
        // R&B now.
        ["Contemporary R&B", "Alternative R&B", "Trap Soul", "Neo-Soul", "New Jack Swing", "Quiet Storm", "Pop Soul"],
        // Smooth, late at night.
        ["Neo-Soul", "Smooth Soul", "Quiet Storm", "Philly Soul", "Pop Soul", "Blue-Eyed Soul", "Soul Jazz", "Acid Jazz",
         "Alternative R&B", "Singer-Songwriter", "Contemporary R&B"],
        // The soul of the sixties and seventies.
        ["Motown", "Northern Soul", "Southern Soul", "Deep Soul", "Philly Soul", "Rhythm and Blues", "Doo-Wop",
         "Blue-Eyed Soul", "Psychedelic Soul", "Gospel Soul", "Pop Soul", "Contemporary R&B"],
        // Funk, and what it became in the eighties.
        ["P-Funk", "Boogie", "Synth Funk", "Minneapolis Sound", "Go-Go", "Jazz-Funk", "Psychedelic Soul", "Funk Rock",
         "Electro-Disco", "Post-Disco", "New Jack Swing", "Contemporary R&B"],

        // ── Disco and the club ──
        ["Euro-Disco", "Italo-Disco", "Hi-NRG", "Electro-Disco", "Nu Disco", "Post-Disco", "Boogie", "French House",
         "Eurodance"],
        ["Big Room", "Future Rave", "Electro House", "Progressive House", "Trance"],
        ["Electroclash", "Electro", "Electropunk", "Synth-Pop", "Electropop"],
        ["Deconstructed Club", "Jersey Club", "Hyperpop", "Bubblegum Bass", "Glitch"],

        // ── Jazz and blues ──
        // Sung, swung and easy.
        ["Vocal Jazz", "Swing", "Big Band", "Jazz Pop", "Smooth Jazz", "Traditional Pop", "Easy Listening", "Cool Jazz",
         "Bossa Nova"],
        ["Bebop", "Hard Bop", "Cool Jazz", "Modal Jazz", "Soul Jazz", "Latin Jazz"],
        ["Free Jazz", "Avant-Garde Jazz", "Free Improvisation", "Modal Jazz"],
        ["Jazz Fusion", "Jazz-Funk", "Acid Jazz", "Soul Jazz", "Smooth Jazz", "Ethio-Jazz"],
        ["Swing", "Big Band", "Gypsy Jazz", "Ragtime", "Jump Blues"],
        ["Chicago Blues", "Electric Blues", "Texas Blues", "British Blues", "Blues Rock", "Jump Blues"],
        ["Delta Blues", "Country Blues", "Piedmont Blues", "Gospel Blues", "Desert Blues"],
        ["Punk Blues", "Garage Rock", "Garage Rock Revival", "Blues Rock"],

        // ── Country and folk ──
        ["Country Pop", "Bro-Country", "Country Rock", "Americana", "Folk Pop"],
        ["Honky Tonk", "Bakersfield Sound", "Outlaw Country", "Western Swing", "Bluegrass", "Americana",
         "Alternative Country", "Gothic Country", "Southern Rock"],
        ["Singer-Songwriter", "Contemporary Folk", "Folk Pop", "Indie Folk", "Alternative Folk", "Folk Rock", "Americana",
         "Acoustic Rock", "Anti-Folk", "Freak Folk", "Chamber Pop"],
        ["Traditional Folk", "Celtic Folk", "Celtic", "Folk Revival", "Neo Folk", "Bluegrass"],

        // ── Reggae, Latin and the world ──
        ["Roots Reggae", "Rocksteady", "Lovers Rock", "Dub", "Nyabinghi", "Ska", "Two-Tone", "Ska Punk"],
        ["Dancehall", "Ragga", "Reggae Fusion", "Reggaeton", "Afrobeats"],
        ["Salsa", "Merengue", "Bachata", "Cumbia", "Son Cubano"],
        ["Bossa Nova", "Samba", "MPB", "Tango", "Latin Jazz"],
        ["Reggaeton", "Trap Latino", "Latin Pop", "Dancehall"],
        ["Mariachi", "Banda", "Norteño", "Vallenato", "Cumbia"],
        ["Latin Rock", "Latin Pop"],
        ["Afrobeat", "Highlife", "Soukous", "Afrobeats", "Ethio-Jazz", "Desert Blues"],
        ["Flamenco", "Fado", "Tango"],
        ["Klezmer", "Balkan Brass"],
        ["Bhangra", "Filmi"],

        // ── Sacred ──
        ["Gospel", "Traditional Gospel", "Contemporary Gospel", "Southern Gospel", "Gospel Soul", "Gospel Blues",
         "Spirituals", "Hymns", "Worship", "Contemporary Christian"],
        ["Gregorian Chant", "Sacred Choral", "Hymns", "Medieval", "Early Music"],
        ["Christian Rock", "Christian Hip-Hop", "Contemporary Christian", "Worship"],

        // ── The screen and the stage ──
        ["Film Score", "Orchestral Score", "Television Score", "Trailer Music", "Video Game Score", "Anime Soundtrack",
         "Synth Score"],
        ["Broadway", "Film Musical", "Show Tunes", "West End", "Original Cast Recording"],
        ["Synth Score", "Synthwave", "Chiptune"],

        // ── Out at the edges ──
        ["Electroacoustic", "Musique Concrete", "Sound Collage", "Spectral Music", "Fluxus", "Field Recording", "Drone"],
        ["Harsh Noise", "Japanoise", "Noisecore", "Power Electronics", "Noise Rock"],
        ["Audiobook", "Podcast", "Interview", "Storytelling", "Poetry", "Comedy"],

        // The classical periods, each with its neighbours.
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
        ranked = withoutClashes(ranked, playing: playing, count: count)

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

    /// What a pick is ranked by: the distance to the song playing, half the distance to the
    /// origin, and ``liveApart`` on a live recording when the radio did not start from one.
    static func score(_ song: RadioSong, playing: RadioSong, origin: RadioSong) -> Double {
        apart(song, playing) + originWeight * apart(song, origin) + (song.live && !origin.live ? liveApart : 0)
    }

    /// `ranked` without the songs whose style clashes with the song playing, while enough are
    /// left: a ballad does not follow dance-pop because it is from the same year. Songs that
    /// share a style or a kin one stay, and so do songs with no style. A song playing with no
    /// style leaves the ranking as it is. The desktop's `WithoutClashes`.
    static func withoutClashes(_ ranked: [RadioSong], playing: RadioSong, count: Int) -> [RadioSong] {
        guard !playing.styles.isEmpty else { return ranked }
        let kept = ranked.filter { styleApart($0.styles, playing.styles) != otherStyle }
        return kept.count >= count + clashSpare ? kept : ranked
    }

    /// Whether a song is a live recording: its record is filed as a live one, or its title or
    /// its album says so. A title says so as "(Live)", "[Live at Wembley]" or " - Unplugged";
    /// an album the same ways, or by starting with the word ("Live", "Live at the BBC") or
    /// holding "Unplugged". "Live Forever" is not live, and a "(Live Mix)" is a mix. The
    /// desktop's `SongRadio.IsLive`; change both together.
    public static func isLive(title: String?, album: String?, releaseType: String?) -> Bool {
        if ReleaseType.fromStored(releaseType) == .live { return true }
        if saysLive(title) { return true }
        guard let album, !album.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return saysLive(album) || has(album, liveAlbum)
    }

    private static func saysLive(_ text: String?) -> Bool {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return has(text, liveNote) && !has(text, liveMix)
    }

    private static func has(_ text: String, _ pattern: NSRegularExpression) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let liveNote = try! NSRegularExpression(
        pattern: #"[(\[][^)\]]*\b(?:live|unplugged)\b[^)\]]*[)\]]|\s[-–—]\s*(?:live|unplugged)\b"#,
        options: [.caseInsensitive])

    private static let liveMix = try! NSRegularExpression(
        pattern: #"\blive\s+(?:mix|edit|dub)\b"#, options: [.caseInsensitive])

    private static let liveAlbum = try! NSRegularExpression(
        pattern: #"^\s*live\s*(?:$|[:\-–—(\[]|(?:at|in|from|on|aus|à|en)\b)|\bunplugged\b"#,
        options: [.caseInsensitive])

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

        // In plain steps with their types written: one chained expression was more than the type
        // checker would take.
        var scored: [(song: RadioSong, score: Double)] = []
        scored.reserveCapacity(crate.songs.count)
        for song in crate.songs {
            if !song.offered || blocked.ids.contains(song.id) || blocked.songs.contains(song.song) { continue }
            let toPlaying: Double = apart(song, playing, related: playingRelated)
            let toOrigin: Double = apart(song, origin, related: originRelated)
            let live: Double = song.live && !origin.live ? liveApart : 0
            scored.append((song: song, score: toPlaying + originWeight * toOrigin + live))
        }
        scored.sort { (a: (song: RadioSong, score: Double), b: (song: RadioSong, score: Double)) -> Bool in
            if a.score != b.score { return a.score < b.score }
            return a.song.id < b.song.id
        }
        return scored.map { $0.song }
    }
}
