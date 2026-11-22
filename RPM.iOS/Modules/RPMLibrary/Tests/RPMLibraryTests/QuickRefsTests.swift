import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// What the person adds to Quick selection, and where it stands. The Android app's `QuickRefTest`.
struct QuickRefsTests {
    private let songs: Set<String> = ["a1", "a2", "b1"]
    private let albums: Set<String> = ["first", "second"]
    private let lists = ["l1": "Road trip"]

    private func resolve(_ ref: String) -> QuickPick? {
        QuickRefs.pick(ref, hasSong: { songs.contains($0) }, hasAlbum: { albums.contains($0) },
                       listName: { lists[$0] })
    }

    private func refOf(_ pick: QuickPick) -> String? {
        QuickRefs.ref(of: pick, listId: { name in lists.first { $0.value == name }?.key })
    }

    private func merged(_ suggested: [QuickPick], _ added: [String], most: Int = 16) -> [String] {
        QuickRefs.merged(suggested, added: added, most: most, resolve: resolve, refOf: refOf)
            .map { name($0) }
    }

    private func name(_ pick: QuickPick) -> String {
        switch pick.kind {
        case .radio: return "radio:" + pick.key
        case .song: return "song:" + pick.key
        case .album: return "album:" + pick.key
        case .playlist: return "list:" + pick.key
        case .station: return "station"
        }
    }

    /// What the person added comes after the suggested mixtapes and before the rest, newest first.
    @Test func addedPicksStandAfterTheMixtapes() {
        let suggested = [QuickPick(kind: .radio, key: "a1"), QuickPick(kind: .song, key: "a2"),
                         QuickPick(kind: .album, key: "first")]
        #expect(merged(suggested, ["album:second", "song:b1"])
                == ["radio:a1", "album:second", "song:b1", "song:a2", "album:first"])
    }

    /// A suggestion the person also added is shown once, where they put it.
    @Test func aSuggestionTheyAddedIsShownOnce() {
        let suggested = [QuickPick(kind: .song, key: "a2"), QuickPick(kind: .album, key: "first")]
        #expect(merged(suggested, ["album:first"]) == ["album:first", "song:a2"])
    }

    /// Something the collection no longer holds is left out, and the line count stays at the most
    /// asked for.
    @Test func missingThingsAreSkippedAndTheCountHolds() {
        let suggested = [QuickPick(kind: .song, key: "a1"), QuickPick(kind: .song, key: "a2"),
                         QuickPick(kind: .song, key: "b1")]
        #expect(merged(suggested, ["song:gone", "album:second"], most: 3)
                == ["album:second", "song:a1", "song:a2"])
    }

    /// A list is stored by its id and shown by its name, as home keys its lists.
    @Test func aListIsStoredByIdAndShownByName() {
        let suggested = [QuickPick(kind: .playlist, key: "Road trip"), QuickPick(kind: .song, key: "a1")]
        #expect(merged(suggested, ["list:l1"]) == ["list:Road trip", "song:a1"])
    }

    @Test func refsReadBack() {
        #expect(resolve(QuickRefs.of(song: "a1")) == QuickPick(kind: .song, key: "a1"))
        #expect(resolve(QuickRefs.of(album: "second")) == QuickPick(kind: .album, key: "second"))
        #expect(resolve("list:none") == nil)
        #expect(resolve("something else") == nil)
        #expect(QuickRefs.songId("song:a1") == "a1")
        #expect(QuickRefs.songId("album:a1") == nil)
    }

    /// Nothing added: the suggestions as they are.
    @Test func nothingAddedIsTheSuggestions() {
        let suggested = [QuickPick(kind: .song, key: "a1"), QuickPick(kind: .album, key: "first")]
        #expect(merged(suggested, []) == ["song:a1", "album:first"])
    }

    /// The newest first, each once, and no more than are kept.
    @Test func addingPutsItFirstAndKeepsAtMostSixteen() {
        var added: [String] = []
        for i in 0..<20 { added = QuickRefs.adding("song:\(i)", to: added) }
        #expect(added.count == QuickRefs.most)
        #expect(added.first == "song:19")
        added = QuickRefs.adding("song:10", to: added)
        #expect(added.first == "song:10")
        #expect(added.filter { $0 == "song:10" }.count == 1)
        #expect(!QuickRefs.removing("song:10", from: added).contains("song:10"))
    }

    /// A starter track or record goes away once the person has music, so it is never kept
    /// (``StarterTracks``).
    @Test func aStarterTrackOrRecordIsNotAdded() throws {
        let song = try #require(StarterTracks.tracks.first)
        let record = try #require(StarterTracks.albums.first)

        #expect(QuickRefs.adding(QuickRefs.of(song: song.rpmId), to: ["song:a"]) == ["song:a"])
        #expect(QuickRefs.adding(QuickRefs.of(album: record.key), to: ["song:a"]) == ["song:a"])
        #expect(QuickRefs.namesStarter(QuickRefs.of(album: record.key)))
        #expect(!QuickRefs.namesStarter("song:a"))
        #expect(!QuickRefs.namesStarter("album:folder:talk talk/laughing stock"))
        #expect(!QuickRefs.namesStarter(QuickRefs.of(list: StarterTracks.prefix + "connect")))
    }
}

/// The songs played lately, at the top of the playlists tab. The Android app's `PlayedLatelyTest`.
struct PlayedLatelyTests {
    private let album = CloudAlbum(key: "k", album: "Record", artist: "Act",
                                   tracks: ["a", "b", "c", "d"].map { CloudTrack(rpmId: $0, title: $0) })

    private func played(_ at: Int64) -> PlayLog.Played { PlayLog.Played(plays: 1, lastPlayedAt: at) }

    /// Newest first, each song once, songs never played left out.
    @Test func newestFirstFromThePlays() {
        let lately = PlayedLately.of([album], played: ["a": played(100), "b": played(300), "c": played(200)])
        #expect(lately.map(\.rpmId) == ["b", "c", "a"])
    }

    /// A song the log holds that the collection does not is left out.
    @Test func aSongNotInTheCollectionIsLeftOut() {
        let lately = PlayedLately.of([album], played: ["gone": played(900), "a": played(100)])
        #expect(lately.map(\.rpmId) == ["a"])
    }

    @Test func atMostAHundred() {
        let many = CloudAlbum(key: "m", album: "Many", artist: "Act",
                              tracks: (0..<150).map { CloudTrack(rpmId: "t\($0)", title: "t\($0)") })
        var log: [String: PlayLog.Played] = [:]
        for i in 0..<150 { log["t\(i)"] = played(Int64(i + 1)) }
        let lately = PlayedLately.of([many], played: log)
        #expect(lately.count == PlayedLately.most)
        #expect(lately.first?.rpmId == "t149")
    }
}
