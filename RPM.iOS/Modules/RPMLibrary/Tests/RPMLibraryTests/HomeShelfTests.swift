import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The home screen's rows. Each row asks a different question of the same shelf.
///
/// Mirrors `RPM.Core.Tests/HomeShelfTests.cs`, keyed by album key where that suite uses a folder. These rows
/// are tested because they are plain arithmetic and the view is not. What a reader sees on that screen is
/// decided entirely by these rows. A row that stopped answering its own question would look just like a
/// working row.
struct HomeShelfTests {
    /// A fixed draw for the tests of the row, not of the drawing. Any number works, as long as it is the same
    /// on every run.
    private let aDraw = 1

    private func album(_ key: String, added: Int64 = 0, plays: Int = 0,
                       lastPlayed: Int64 = 0) -> HomeAlbum {
        HomeAlbum(key: key, album: key, artist: "Somebody", genres: [], year: 0,
                  addedAt: added, plays: plays, lastPlayedAt: lastPlayed)
    }

    private func traits(_ key: String, _ artist: String,
                        _ genre: String? = nil, year: Int = 0) -> AlbumTraits {
        AlbumTraits(key: key, album: key, artist: artist,
                    genres: genre.map { [$0] } ?? [], year: year)
    }

    private func shelf(_ count: Int) -> [AlbumTraits] {
        (0..<count).map {
            traits("a\($0)", "Act \($0 % 12)", ["Rock", "Jazz", "Folk"][$0 % 3], year: 1970 + $0 % 30)
        }
    }

    // ── what has been on ──

    @Test func recentlyListenedIsTheNewestListenFirst() {
        let shelf = [album("old", lastPlayed: 10),
                     album("newest", lastPlayed: 30),
                     album("middle", lastPlayed: 20)]

        #expect(HomeShelf.listened(shelf, count: 10) == ["newest", "middle", "old"])
    }

    /// A record nobody has played is not a recent listen. A row that fell back to the rest of the collection
    /// would say "you listened to this" about music nobody has heard.
    @Test func aRecordNeverPlayedIsNotARecentListen() {
        #expect(HomeShelf.listened([album("never"), album("also-never", added: 99)],
                                   count: 10).isEmpty)
    }

    /// Two reads of an unchanged shelf give the same row. A row that changes order when the reader
    /// does nothing looks like a bug.
    @Test func anUnchangedShelfGivesTheSameRowTwice() {
        let shelf = [album("b", lastPlayed: 5), album("a", lastPlayed: 5), album("c", lastPlayed: 5)]

        #expect(HomeShelf.listened(shelf, count: 10) == ["a", "b", "c"])
        #expect(HomeShelf.listened(shelf, count: 10) == HomeShelf.listened(shelf.reversed(), count: 10))
    }

    // ── what has been played most ──

    /// Counts the tracks played. A record played all the way through ranks above one song played again and
    /// again. That is what most played means for a shelf of albums.
    @Test func mostPlayedCountsTheTracksAndNotTheRecords() {
        let shelf = [album("one-song-on-repeat", plays: 8), album("played-through", plays: 12)]

        #expect(HomeShelf.played(shelf, count: 10) == ["played-through", "one-song-on-repeat"])
    }

    @Test func aRecordNeverPlayedIsNotMostPlayed() {
        #expect(HomeShelf.played([album("never", added: 99)], count: 10).isEmpty)
    }

    // ── what arrived last ──

    /// A collection opened for the first time can fill this row, which is why it does not use play counts.
    @Test func recentlyAddedAnswersForACollectionNobodyHasPlayed() {
        let shelf = [album("first", added: 1), album("last", added: 9)]

        #expect(HomeShelf.added(shelf, count: 10) == ["last", "first"])
    }

    @Test func aRowIsNoLongerThanItIsAskedFor() {
        let shelf = (0..<50).map { album("a\($0)", added: Int64($0)) }

        #expect(HomeShelf.added(shelf, count: 5).count == 5)
        #expect(HomeShelf.added(shelf, count: 0).isEmpty)
    }

    /// The row the taste is read from: what has been played, or, if nothing has, what arrived last.
    /// A borrowed shelf has records but no listening.
    @Test func theBasisFallsBackToWhatArrivedLast() {
        #expect(HomeShelf.basis(listened: ["a"], added: ["b"]) == ["a"])
        #expect(HomeShelf.basis(listened: [], added: ["b"]) == ["b"])
    }

    // ── what to play next ──

    /// A suggestion is a record the listener has not just played. The recently played row is
    /// directly above this one on the same screen.
    @Test func nothingSuggestedIsAlreadyInTheRowAboveIt() {
        let library = [traits("played/one", "A", "Rock"),
                       traits("played/two", "B", "Rock"),
                       traits("unplayed", "C", "Rock")]

        let row = HomeShelf.suggested(seeds: [library[0]], traits: library,
                                      exclude: ["played/one", "played/two"], count: 10, draw: aDraw)

        #expect(row == ["unplayed"])
    }

    /// Every seed gets a card near the front. The first seed must not fill the whole row, because
    /// readers look at the front of a row, and the front should reflect their week of listening.
    @Test func theFrontOfTheRowAnswersToEverySeed() {
        let library = [traits("rock/seed", "Rock Act", "Rock"),
                       traits("rock/a", "Rock Other", "Rock"),
                       traits("rock/b", "Rock Third", "Rock"),
                       traits("jazz/seed", "Jazz Act", "Jazz"),
                       traits("jazz/a", "Jazz Other", "Jazz"),
                       traits("jazz/b", "Jazz Third", "Jazz")]

        let row = HomeShelf.suggested(seeds: [library[0], library[3]], traits: library,
                                      exclude: ["rock/seed", "jazz/seed"], count: 4, draw: aDraw)

        #expect(Set(row.prefix(2).map { $0.split(separator: "/")[0] }).count == 2)
    }

    /// A listener who has played nothing has no taste to read. The correct answer is an empty row, not the
    /// collection in some order.
    @Test func nothingPlayedSuggestsNothing() {
        #expect(HomeShelf.suggested(seeds: [], traits: [traits("a", "A")],
                                    exclude: [], count: 10, draw: aDraw).isEmpty)
    }

    /// A shelf too small to fill the row is the case for every new collection. The round robin must
    /// stop, and not loop forever looking for a card that does not exist.
    @Test func aShelfTooSmallToFillTheRowStillReturns() {
        let library = [traits("seed", "A", "Rock"), traits("other", "B", "Rock")]

        let row = HomeShelf.suggested(seeds: [library[0]], traits: library,
                                      exclude: ["seed"], count: 20, draw: aDraw)

        #expect(row == ["other"])
    }

    /// The same draw gives the same row. A screen that is read again while the user is looking at it must not
    /// rearrange itself.
    @Test func theSameDrawGivesTheSameRow() {
        let library = shelf(60)

        let once = HomeShelf.suggested(seeds: [library[0]], traits: library,
                                       exclude: [], count: 10, draw: 4242)
        let again = HomeShelf.suggested(seeds: [library[0]], traits: library,
                                        exclude: [], count: 10, draw: 4242)

        #expect(once == again)
    }

    /// A different draw gives a different row. That is the purpose: the seeds do not change until
    /// something else is played, so without different draws the row would show the same records
    /// forever.
    @Test func anotherDrawGivesAnotherRow() {
        let library = shelf(60)

        let rows = Set((1...5).map { draw in
            HomeShelf.suggested(seeds: [library[0]], traits: library,
                                exclude: [], count: 10, draw: draw).joined(separator: ",")
        })

        #expect(rows.count >= 4)
    }

    /// The draw shuffles the pool that the ranking offers. It never picks from outside that pool.
    @Test func theDrawStaysInsideWhatTheRankingOffered() {
        let library = shelf(60)
        let offered = Set(SimilarAlbums.pick(subject: library[0], library: library,
                                             count: 10 * HomeShelf.pool).map(\.key))

        let row = HomeShelf.suggested(seeds: [library[0]], traits: library,
                                      exclude: [], count: 10, draw: 7)

        #expect(row.allSatisfy { offered.contains($0) })
    }

    // ── what they are into ──

    /// The taste row is based on the acts and the kinds of music the listener plays most, across all of their
    /// listening, not only the last few records.
    @Test func theTasteRowIsTheActsAndKindsTheyPlay() {
        let library = [traits("theirs", "Talk Talk", "Post-Rock"),
                       traits("nothing-like-it", "Somebody Else", "Techno")]

        let row = HomeShelf.fromTaste(
            artists: [PlayedArtist(name: "Talk Talk", plays: 40)],
            genres: [GenreShare(genre: "Post-Rock", share: 0.8)],
            traits: library, played: [], exclude: [], count: 10, draw: aDraw)

        #expect(row == ["theirs"])
    }

    /// A listener who has played nothing has no taste. This row is empty, not the shelf in some order.
    @Test func noListeningIsNoTasteRow() {
        #expect(HomeShelf.fromTaste(artists: [], genres: [], traits: [traits("a", "A")],
                                    played: [], exclude: [], count: 10, draw: aDraw).isEmpty)
    }

    /// Records already played score less than unheard ones, so while there are unheard records to
    /// offer, they fill the row. The draw shuffles the pool that the scoring chose. So the test
    /// checks which records reach that pool, not which of them comes out first.
    @Test func whatHasNotBeenPlayedFillsTheRowWhileThereIsAnyOfIt() {
        var library = (0..<10).map { traits("unheard\($0)", "Talk Talk", "Post-Rock") }
        library.append(traits("heard", "Talk Talk", "Post-Rock"))

        let row = HomeShelf.fromTaste(
            artists: [PlayedArtist(name: "Talk Talk", plays: 40)],
            genres: [GenreShare(genre: "Post-Rock", share: 0.8)],
            traits: library, played: ["heard"], exclude: [], count: 3, draw: aDraw)

        #expect(row.count == 3)
        #expect(row.contains("heard") == false)
    }

    /// The score for played records is a fraction, not zero. Otherwise a listener with a small
    /// collection, or one who has played most of it, would get an empty row. A record played a year
    /// ago is fair to offer again.
    @Test func aShelfEverythingHasBeenPlayedOnStillFillsTheRow() {
        let library = [traits("heard", "Talk Talk", "Post-Rock"),
                       traits("also-heard", "Talk Talk", "Post-Rock")]

        let row = HomeShelf.fromTaste(
            artists: [PlayedArtist(name: "Talk Talk", plays: 40)],
            genres: [GenreShare(genre: "Post-Rock", share: 0.8)],
            traits: library, played: ["heard", "also-heard"], exclude: [], count: 10, draw: aDraw)

        #expect(Set(row) == ["heard", "also-heard"])
    }

    // ── the banner's reach ──

    /// A ranked row keeps its own order, but the banner may show any record that answers the
    /// question well. If the banner used only the row's order, it would show the same record
    /// forever.
    @Test func theBannerVariesTheFrontOfARankedRow() {
        let ranked = (0..<20).map { "a\($0)" }

        let drawn = Set((1...5).map {
            HomeShelf.varied(ranked, draw: $0, salt: "played",
                             reach: HomeShelf.bannerReach).first ?? ""
        })

        #expect(drawn.count >= 2)
        #expect(drawn.allSatisfy { ranked.prefix(HomeShelf.bannerReach).contains($0) })
    }

    @Test func theTailOfARankedRowIsLeftWhereItIs() {
        let ranked = (0..<20).map { "a\($0)" }

        let varied = HomeShelf.varied(ranked, draw: 3, salt: "played", reach: 8)

        #expect(Array(varied.suffix(12)) == Array(ranked.suffix(12)))
        #expect(Set(varied) == Set(ranked))
    }
}
