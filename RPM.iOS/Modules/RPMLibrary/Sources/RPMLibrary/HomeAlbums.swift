import Foundation
import RPMKit

/// The library and the play log, turned into the rows that the home screen asks its
/// questions of.
///
/// This is one pass over the listing, not one pass per row. The questions differ, but the
/// facts that they are asked about are the same.
public enum HomeAlbums {
    /// Every record on the shelf, with how much it has been played on ANY of the listener's
    /// devices.
    ///
    /// A record's plays are the plays of its tracks added up. This is what makes Most played
    /// show the records that were listened to most, not the ones that are owned most. The
    /// last-played stamp is the newest of its tracks' stamps, because a record is listened to
    /// over its whole length.
    public static func of(_ albums: [CloudAlbum], log: PlayLog) async -> [HomeAlbum] {
        // One read of the log, not two per track. See PlayLog.everythingPlayed.
        of(albums, played: await log.everythingPlayed())
    }

    /// The same, from a reading of the log that is already in hand.
    ///
    /// **The whole screen is built from one reading.** The rows and the quick selection are
    /// two questions about the same listening. If they were asked of two separate readings,
    /// they could disagree about which record was played most while somebody is looking at both.
    public static func of(_ albums: [CloudAlbum],
                          played: [String: PlayLog.Played]) -> [HomeAlbum] {
        var shelf: [HomeAlbum] = []
        shelf.reserveCapacity(albums.count)

        // One reading of each genre spelling for the whole shelf. See Genres.of.
        var readings: [String: String?] = [:]

        for album in albums {
            var plays = 0
            var lastPlayedAt: Int64 = 0
            var addedAt: Int64 = 0
            var years: [Int: Int] = [:]

            for track in album.tracks {
                if let heard = played[track.rpmId] {
                    plays += heard.plays
                    lastPlayedAt = max(lastPlayedAt, heard.lastPlayedAt)
                }
                addedAt = max(addedAt, track.addedAt)

                if let year = track.tags?.year, year > 0 {
                    years[year, default: 0] += 1
                }
            }

            shelf.append(HomeAlbum(
                key: album.key,
                album: album.album,
                artist: album.artist,
                // The app's genres, read in the same way as the desktop home reads them. So
                // "Hip Hop" and "hip-hop" are one genre for the suggestions and for the
                // listening taste.
                genres: Genres.of(album.tracks, readings: &readings),
                // The year that most of its tracks agree on. A compilation has as many years as
                // it has songs. Any one of them, read as the record's year, would put the record
                // wherever its first track happened to be.
                year: AlbumSort.yearFrom(years.map { ($0.key, $0.value) }),
                addedAt: addedAt,
                plays: plays,
                lastPlayedAt: lastPlayedAt))
        }

        return shelf
    }
}

/// What the listener is into, read off what they have actually played.
///
/// The desktop reads this from its listening log, which holds the hour and the day of every
/// listen. This platform keeps counters and no log. So the same two answers are worked out
/// from the shelf instead. An act's plays are the plays of its records. A genre's share is
/// the plays of its records divided by all the plays. This is the same question asked of
/// thinner evidence. The row that shows it says so by being about a taste, not about an evening.
public enum ListeningTaste {
    public struct Taste: Sendable, Equatable {
        public let artists: [PlayedArtist]
        public let genres: [GenreShare]
    }

    public static func of(_ shelf: [HomeAlbum]) -> Taste {
        var byAct: [String: (name: String, plays: Int)] = [:]
        var byGenre: [String: Int] = [:]
        var played = 0

        for album in shelf where album.plays > 0 {
            played += album.plays

            let act = SimilarAlbums.fold(album.artist)
            if !act.isEmpty {
                // The first spelling met stands for the rest. Two spellings of one band count as
                // one act. Which spelling is shown matters less than not counting them as two
                // small acts.
                let held = byAct[act]
                byAct[act] = (held?.name ?? album.artist, (held?.plays ?? 0) + album.plays)
            }

            for genre in album.genres {
                byGenre[genre, default: 0] += album.plays
            }
        }

        let artists = byAct.values
            .map { PlayedArtist(name: $0.name, plays: $0.plays) }
            .sorted { $0.plays == $1.plays ? $0.name < $1.name : $0.plays > $1.plays }

        // The share is of everything played, not of only the plays that carry a genre. So a
        // collection where half the tracks are untagged does not look as if its tagged half
        // were the whole taste.
        var genres: [GenreShare] = []
        if played > 0 {
            genres = byGenre.map { genre, plays in
                GenreShare(genre: genre, share: Double(plays) / Double(played))
            }
            genres.sort { $0.share == $1.share ? $0.genre < $1.genre : $0.share > $1.share }
        }

        return Taste(artists: artists, genres: genres)
    }
}
