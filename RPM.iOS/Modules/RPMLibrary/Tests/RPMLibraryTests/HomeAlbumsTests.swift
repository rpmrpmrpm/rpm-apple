import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// Turns the library and the play log into the rows that the home screen uses for its questions.
struct HomeAlbumsTests {
    private func track(_ id: String, album: String, artist: String = "Talk Talk",
                       genre: String? = nil, year: Int = 0, addedAt: Int64 = 0) -> CloudTrack {
        var tags = CloudTrackTags()
        tags.genre = genre
        tags.year = year
        return CloudTrack(rpmId: id, relativePath: "\(artist)/\(album)/\(id).flac", title: id,
                          artist: artist, album: album, addedAt: addedAt, tags: tags)
    }

    private func album(_ key: String, tracks: [CloudTrack]) -> CloudAlbum {
        CloudAlbum(key: key, album: key, artist: tracks.first?.artist ?? "", tracks: tracks)
    }

    /// The rows describe the listener's listening on all their devices, not only this phone. A phone that
    /// ranked only its own plays would show the wrong shelf to someone who mostly listens on a desk computer.
    @Test func playsComeFromEveryDeviceAndNotJustThisOne() async {
        let log = PlayLog(inMemory: true)
        _ = await log.apply([CloudTrackPlays(rpmId: "t1", deviceId: "desk", plays: 9,
                                             lastPlayedAt: 900, updatedAt: 1)], mine: "phone", in: log.pass())

        let shelf = await HomeAlbums.of([album("k1", tracks: [track("t1", album: "Spirit of Eden")])],
                                        log: log)

        #expect(shelf[0].plays == 9)
        #expect(shelf[0].lastPlayedAt == 900)
    }

    /// A record's plays are the sum of its tracks' plays. This makes Most played mean most listened
    /// to, not most owned.
    @Test func aRecordsPlaysAreItsTracksAddedUp() async {
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 100)
        await log.note(rpmId: "t2", at: 200)
        await log.note(rpmId: "t2", at: 300)

        let shelf = await HomeAlbums.of([album("k1", tracks: [
            track("t1", album: "Spirit of Eden"), track("t2", album: "Spirit of Eden"),
        ])], log: log)

        #expect(shelf[0].plays == 3)
        // The newest play of its tracks is used. A record is played over its full length, and a record still
        // playing must not sort below one that finished an hour ago.
        #expect(shelf[0].lastPlayedAt == 300)
    }

    @Test func aRecordNobodyHasPlayedCountsNothing() async {
        let log = PlayLog(inMemory: true)

        let shelf = await HomeAlbums.of([album("k1", tracks: [track("t1", album: "Laughing Stock")])],
                                        log: log)

        #expect(shelf[0].plays == 0)
        #expect(shelf[0].lastPlayedAt == 0)
    }

    /// The year and the genres belong to the record, so they are read from its tracks. Tags are
    /// stored per file, but the ranking works on whole records. The genres are the app's own, as on
    /// the desktop's home.
    @Test func aRecordCarriesItsGenresAndItsYear() async {
        let log = PlayLog(inMemory: true)

        let shelf = await HomeAlbums.of([album("k1", tracks: [
            track("t1", album: "Spirit of Eden", genre: "Hard Rock", year: 1988),
            track("t2", album: "Spirit of Eden", genre: "Post-Punk", year: 1988),
        ])], log: log)

        #expect(shelf[0].genres == ["Rock", "Punk"])
        #expect(shelf[0].year == 1988)
    }

    /// Two spellings of one genre are one genre. If they were kept apart, "Deep House" and "House" would look
    /// like two kinds of music with nothing in common.
    @Test func twoSpellingsOfOneGenreAreOneGenre() async {
        let log = PlayLog(inMemory: true)

        let shelf = await HomeAlbums.of([
            album("a", tracks: [track("t1", album: "A", genre: "Deep House"),
                                track("t2", album: "A", genre: "house")]),
            album("b", tracks: [track("t3", album: "B", genre: "House")]),
        ], log: log)

        #expect(shelf[0].genres == ["House"])
        #expect(shelf[1].genres == ["House"])
    }

    /// A tag that is not one of the app's genres is dropped. Two records that share a misspelt tag
    /// are not proof that they are alike.
    @Test func aTagThatIsNoneOfTheAppsGenresIsDropped() async {
        let log = PlayLog(inMemory: true)

        let shelf = await HomeAlbums.of([album("k1", tracks: [
            track("t1", album: "A", genre: "zzqx not a genre"),
            track("t2", album: "A", genre: "Techno"),
        ])], log: log)

        #expect(shelf[0].genres == ["Techno"])
    }

    /// The taste uses the same genres, so plays of "Deep House" and of "House" count as one genre, not two.
    @Test func theTasteCountsTwoSpellingsAsOneGenre() {
        let played = ["t1": PlayLog.Played(plays: 3, lastPlayedAt: 1),
                      "t2": PlayLog.Played(plays: 1, lastPlayedAt: 1)]
        let shelf = HomeAlbums.of([
            album("a", tracks: [track("t1", album: "A", artist: "Kerri Chandler", genre: "Deep House")]),
            album("b", tracks: [track("t2", album: "B", artist: "Larry Heard", genre: "House")]),
        ], played: played)

        let taste = ListeningTaste.of(shelf)

        #expect(taste.genres.map(\.genre) == ["House"])
        #expect(abs((taste.genres.first?.share ?? 0) - 1) < 0.0001)
    }

    /// The newest of its tracks is used. A record arrives over the minutes its files take to copy
    /// in. A record still arriving must not sort below one that arrived yesterday.
    @Test func aRecordArrivedWhenItsNewestTrackDid() async {
        let log = PlayLog(inMemory: true)

        let shelf = await HomeAlbums.of([album("k1", tracks: [
            track("t1", album: "Spirit of Eden", addedAt: 10),
            track("t2", album: "Spirit of Eden", addedAt: 40),
        ])], log: log)

        #expect(shelf[0].addedAt == 40)
    }
}

/// What the listener likes, based on what they have played.
struct ListeningTasteTests {
    private func shelf(_ entries: [(key: String, artist: String, genre: String?, plays: Int)]) -> [HomeAlbum] {
        entries.map {
            HomeAlbum(key: $0.key, album: $0.key, artist: $0.artist,
                      genres: $0.genre.map { [$0] } ?? [], year: 0,
                      addedAt: 0, plays: $0.plays, lastPlayedAt: $0.plays > 0 ? 1 : 0)
        }
    }

    @Test func theActsAreOrderedByWhatHasBeenPlayedOfThem() {
        let taste = ListeningTaste.of(shelf([
            (key: "a", artist: "Talk Talk", genre: "Post-Rock", plays: 3),
            (key: "b", artist: "Slowdive", genre: "Shoegaze", plays: 9),
        ]))

        #expect(taste.artists.map(\.name) == ["Slowdive", "Talk Talk"])
        #expect(taste.artists.first?.plays == 9)
    }

    /// An act's records are added together. A listener who plays four records by one band is shown
    /// as listening to that band, not to four small acts.
    @Test func anActsRecordsAreAddedTogether() {
        let taste = ListeningTaste.of(shelf([
            (key: "a", artist: "Talk Talk", genre: nil, plays: 3),
            (key: "b", artist: "Talk Talk", genre: nil, plays: 4),
        ]))

        #expect(taste.artists.count == 1)
        #expect(taste.artists.first?.plays == 7)
    }

    /// Shares are calculated over all plays, not only over the genres kept. So a listener whose top
    /// genres make up a third of their listening is not shown as listening only to those genres.
    @Test func theGenreSharesAreOfEverythingPlayed() {
        let taste = ListeningTaste.of(shelf([
            (key: "a", artist: "Talk Talk", genre: "Post-Rock", plays: 3),
            (key: "b", artist: "Slowdive", genre: "Shoegaze", plays: 1),
        ]))

        #expect(taste.genres.first?.genre == "Post-Rock")
        #expect(abs((taste.genres.first?.share ?? 0) - 0.75) < 0.0001)
    }

    /// A record that nobody has played says nothing about the listener's taste.
    @Test func whatHasNotBeenPlayedIsNotTaste() {
        let taste = ListeningTaste.of(shelf([
            (key: "a", artist: "Talk Talk", genre: "Post-Rock", plays: 0),
        ]))

        #expect(taste.artists.isEmpty)
        #expect(taste.genres.isEmpty)
    }
}
