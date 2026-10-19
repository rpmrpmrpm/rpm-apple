import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The popular tracks at the top of an artist's page, and the per-record play counts they are ranked from.

private func track(_ id: String, _ title: String, disc: Int = 1, at position: Int,
                   release: String? = nil) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.discNumber = disc
    tags.trackNumber = position
    tags.musicBrainzReleaseId = release
    return CloudTrack(rpmId: id, title: title, artist: "Adele", tags: tags)
}

/// A record of `count` songs, titled "<key> 1" and on, numbered from one.
private func record(_ key: String, songs count: Int) -> CloudAlbum {
    CloudAlbum(key: key, album: key, artist: "Adele",
               tracks: (1...count).map { track("\(key)#\($0)", "\(key) \($0)", at: $0) })
}

private func songs(_ albums: [CloudAlbum]) -> [ArtistShelves.ArtistSong] {
    albums.flatMap { album in album.tracks.map { ArtistShelves.ArtistSong(track: $0, album: album) } }
}

/// Builds play counts for positions 1, 2, and so on, on disc one.
private func listens(_ values: Int64...) -> [TrackPlace: Int64] {
    Dictionary(uniqueKeysWithValues: values.enumerated().map {
        (TrackPlace(disc: 1, position: $0.offset + 1), $0.element)
    })
}

@Suite struct ArtistPopularTests {
    @Test func theMostPlayedComeFirst() {
        let albums = [record("21", songs: 6), record("25", songs: 6)]

        let ranked = ArtistPopular.ranked(songs(albums), plays: [
            "21": listens(10, 900, 30, 0, 5, 1),
            "25": listens(800, 20, 0, 0, 0, 2),
        ])

        #expect(ranked.map(\.track.title) == ["21 2", "25 1", "21 3", "25 2", "21 1", "21 5"])
    }

    /// At most half of an artist's songs are listed. Twelve songs give at most six.
    @Test func atMostHalfOfTheirSongs() {
        let albums = [record("21", songs: 12)]

        let ranked = ArtistPopular.ranked(songs(albums), plays: [
            "21": listens(12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1),
        ])

        #expect(ranked.count == 6)
    }

    @Test func atMostTwelve() {
        let albums = [record("21", songs: 20), record("25", songs: 20)]
        let many = listens(20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1)

        let ranked = ArtistPopular.ranked(songs(albums), plays: ["21": many, "25": many])

        #expect(ranked.count == ArtistPopular.most)
    }

    /// If fewer than four songs have listens, the section is not shown.
    @Test func tooFewIsNone() {
        let albums = [record("21", songs: 10)]

        let ranked = ArtistPopular.ranked(songs(albums), plays: ["21": listens(5, 4, 3)])

        #expect(ranked.isEmpty)
    }

    /// An artist with six songs gets no section. Half of six is three, which is below the minimum of four.
    @Test func aShortListingHasNoSection() {
        let albums = [record("21", songs: 6)]

        let ranked = ArtistPopular.ranked(songs(albums), plays: ["21": listens(6, 5, 4, 3, 2, 1)])

        #expect(ranked.isEmpty)
    }

    /// A song on both the studio record and a live record is listed once, using the copy with more plays.
    @Test func oneSongPerTitle() {
        let studio = CloudAlbum(key: "21", album: "21", artist: "Adele", tracks: [
            track("s1", "Rolling in the Deep", at: 1), track("s2", "Rumour Has It", at: 2),
            track("s3", "Turning Tables", at: 3), track("s4", "Set Fire to the Rain", at: 4),
        ])
        let live = CloudAlbum(key: "live", album: "Live", artist: "Adele", tracks: [
            track("l1", "Rolling in the Deep (Live)", at: 1), track("l2", "Someone Like You", at: 2),
            track("l3", "Hometown Glory", at: 3), track("l4", "Chasing Pavements", at: 4),
        ])

        let ranked = ArtistPopular.ranked(songs([studio, live]), plays: [
            "21": listens(9000, 500, 400, 300),
            "live": listens(100, 8000, 50, 40),
        ])

        #expect(ranked.map(\.id) == ["s1", "l2", "s2", "s3"])
    }

    /// A song is matched by its disc and its position.
    @Test func theDiscIsPartOfThePlace() {
        let deluxe = CloudAlbum(key: "d", album: "25 (Deluxe)", artist: "Adele", tracks:
            (1...4).map { track("a\($0)", "Song \($0)", disc: 1, at: $0) }
            + (1...4).map { track("b\($0)", "Demo \($0)", disc: 2, at: $0) })

        var plays = listens(400, 300, 200, 100)
        for at in 1...4 { plays[TrackPlace(disc: 2, position: at)] = Int64(at) }

        let ranked = ArtistPopular.ranked(songs([deluxe]), plays: ["d": plays])

        #expect(ranked.map(\.id) == ["a1", "a2", "a3", "a4"])
    }

    /// A record with no play data adds no songs, and the other records are still ranked.
    @Test func aRecordWithNoAnswerAddsNothing() {
        let albums = [record("21", songs: 6), record("25", songs: 6)]

        let ranked = ArtistPopular.ranked(songs(albums), plays: ["21": listens(6, 5, 4, 3, 2, 1)])

        #expect(ranked.count == 6)
        #expect(ranked.allSatisfy { $0.album.key == "21" })
    }

    @Test func aTrackWithNoNumberIsLeftOut() {
        let album = CloudAlbum(key: "x", album: "x", artist: "Adele", tracks:
            [track("n", "No number", at: 0)] + (1...9).map { track("t\($0)", "T \($0)", at: $0) })

        let ranked = ArtistPopular.ranked(songs([album]), plays: [
            "x": listens(9, 8, 7, 6, 5, 4, 3, 2, 1),
        ])

        #expect(!ranked.map(\.id).contains("n"))
    }

    @Test func theRecordsHoldingMostOfTheirSongsAreAskedFirst() {
        let albums = [record("single", songs: 1), record("album", songs: 9), record("ep", songs: 4)]

        #expect(ArtistPopular.records(songs(albums)).map(\.key) == ["album", "ep", "single"])
    }

    @Test func aBracketedAsideDoesNotMakeAnotherSong() {
        #expect(ArtistPopular.title(of: track("a", "Hello (Live at the BBC)", at: 1))
                == ArtistPopular.title(of: track("b", "hello", at: 1)))
        #expect(ArtistPopular.title(of: track("c", "Skyfall [Remastered]", at: 1)) == "skyfall")
    }
}

// ── the plays store ──

private let twentyOne = WorldPlays.Record(artist: "Adele", album: "21", tracks: 11, release: nil)

private let answer = RecordPlays(
    tracks: [.init(position: 1, title: "Rolling in the Deep", recordingMbid: "a")],
    plays: [.init(recordingMbid: "a", listens: 9000, listeners: 100)])

private struct Down: Error {}

@MainActor
@Suite struct WorldPlaysTests {
    @Test func aRecordIsAskedAboutOnce() async {
        let asked = Counter()
        let store = WorldPlays { _ in asked.bump(); return (answer, false) }

        #expect(await store.plays(twentyOne) == [TrackPlace(disc: 1, position: 1): 9000])
        #expect(await store.plays(twentyOne) == [TrackPlace(disc: 1, position: 1): 9000])
        #expect(asked.value == 1)
        #expect(store.cached(twentyOne) != nil)
    }

    /// "No catalogue has the record" is a valid answer, so it is kept.
    @Test func noRecordIsKeptAsAnAnswer() async {
        let asked = Counter()
        let store = WorldPlays { _ in asked.bump(); return (.empty, false) }

        #expect(await store.plays(twentyOne) == [:])
        #expect(await store.plays(twentyOne) == [:])
        #expect(asked.value == 1)
    }

    /// A request that could not be made is not the same as "nobody plays this record".
    @Test func aFailureIsNotKept() async {
        let asked = Counter()
        let store = WorldPlays { _ in asked.bump(); throw Down() }

        #expect(await store.plays(twentyOne) == nil)
        #expect(await store.plays(twentyOne) == nil)
        #expect(asked.value == 2)
        #expect(store.cached(twentyOne) == nil)
    }

    /// A partial answer is used but not stored. The API finishes its data later, so the next ask
    /// fetches again.
    @Test func aPartialAnswerIsNotKept() async {
        let asked = Counter()
        let store = WorldPlays { _ in asked.bump(); return (answer, true) }

        #expect(await store.plays(twentyOne) != nil)
        #expect(store.cached(twentyOne) == nil)
        _ = await store.plays(twentyOne)
        #expect(asked.value == 2)
    }

    @Test func twoAsksAtOnceMakeOneRequest() async {
        let asked = Counter()
        let store = WorldPlays { _ in
            asked.bump()
            try await Task.sleep(for: .milliseconds(50))
            return (answer, false)
        }

        async let first = store.plays(twentyOne)
        async let second = store.plays(twentyOne)
        let both = await [first, second]

        #expect(both.allSatisfy { $0 == [TrackPlace(disc: 1, position: 1): 9000] })
        #expect(asked.value == 1)
    }

    /// The record is asked about the same way as the desktop's sweep, including the release id when the
    /// files have one.
    @Test func aRecordIsAskedWithItsTaggedRelease() {
        let album = CloudAlbum(key: "k", album: "21", artist: "Adele", tracks: [
            track("1", "One", at: 1), track("2", "Two", at: 2, release: "rel-21"),
        ])

        #expect(WorldPlays.Record(album) == WorldPlays.Record(artist: "Adele", album: "21", tracks: 2,
                                                             release: "rel-21"))
    }

    @Test func signingOutForgetsTheAnswers() async {
        let asked = Counter()
        let store = WorldPlays { _ in asked.bump(); return (answer, false) }

        _ = await store.plays(twentyOne)
        store.forget()
        _ = await store.plays(twentyOne)

        #expect(asked.value == 2)
    }
}
