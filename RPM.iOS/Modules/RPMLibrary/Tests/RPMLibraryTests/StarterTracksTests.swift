import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The starter tracks the iPhone shows in place of an empty collection, and how the cloud is kept
/// away from them. The Android app's `StarterTracksTest`.
struct StarterTracksTests {
    private let starters = StarterTracks.albums

    private var mine: [CloudAlbum] {
        var tags = CloudTrackTags()
        tags.durationSeconds = 200
        return AlbumWall.group([
            CloudTrack(rpmId: "8114221e-17e5-493e-872f-96946345e7ef", relativePath: "Act/Record/song.flac",
                       title: "Song", artist: "Act", album: "Record", tags: tags),
        ])
    }

    // ── when they are shown ──

    @Test func anEmptyCollectionTheStoreAnsweredForShowsThem() {
        #expect(StarterTracks.shown([], starters: starters, reached: true).map(\.key) == starters.map(\.key))
    }

    @Test func oneSongOfTheirOwnTakesThemAway() {
        #expect(StarterTracks.shown(mine, starters: starters, reached: true).map(\.key) == mine.map(\.key))
    }

    /// A read that failed gives no records too, and that is not an empty collection.
    @Test func aCollectionThatCouldNotBeReadDoesNotShowThem() {
        #expect(StarterTracks.shown([], starters: starters, reached: false).isEmpty)
    }

    /// The Apple TV hands the session no starter tracks, so an empty collection stays empty there.
    @Test func anAppThatShipsNoneShowsNone() {
        #expect(StarterTracks.shown([], starters: [], reached: true).isEmpty)
        #expect(StarterTracks.shown([], starters: [], reached: true, force: true).isEmpty)
    }

    @Test func thePreviewShowsThemOverMusic() {
        #expect(StarterTracks.shown(mine, starters: starters, reached: true, force: true).map(\.key)
                == starters.map(\.key))
        #expect(StarterTracks.shown(mine, starters: starters, reached: false, force: true).map(\.key)
                == starters.map(\.key))
    }

    // ── what they are ──

    @Test func threeRecordsOfOneTrackEach() {
        #expect(starters.count == 3)
        for album in starters {
            #expect(album.tracks.count == 1)
            #expect(StarterTracks.isStarter(album))
            #expect(StarterTracks.isStarterKey(album.key), "\(album.key)")
            #expect(StarterTracks.record(of: album)?.track.rpmId == album.tracks[0].rpmId)
        }
        #expect(Set(starters.map(\.album)) == ["Connect - Single", "Gymnopedie no. 1", "Moonlight Sonata"])
    }

    /// The welcome needs a song of at least 90 seconds, and the player shows the record's names.
    @Test func everyTrackIsNamedAndLongEnoughForTheWelcome() {
        for track in StarterTracks.tracks {
            #expect(!(track.title ?? "").isEmpty)
            #expect(!(track.artist ?? "").isEmpty)
            #expect((track.tags?.durationSeconds ?? 0) >= WelcomeSong.shortest, "\(track.rpmId)")
        }
        #expect(Set(StarterTracks.welcomeOrder) == Set(StarterTracks.tracks.map(\.rpmId)))
    }

    /// The levelling reads the catalogue row, so each track carries its measured loudness.
    @Test func everyTrackKnowsHowLoudItIs() {
        for track in StarterTracks.tracks {
            #expect(track.tags?.hasLoudness == true, "\(track.rpmId)")
            #expect((track.tags?.truePeak ?? 0) > 0, "\(track.rpmId)")
        }
    }

    /// The iPhone decodes the shipped files itself, so they are never asked of the cloud.
    @Test func theFilesAreOnesThisDeviceDecodes() {
        for track in StarterTracks.tracks {
            #expect(PlaysHere.decodes(track), "\(track.rpmId)")
        }
    }

    @Test func onlyTheMoonlightSonataHasADisc() {
        #expect(StarterTracks.records.filter(\.hasDisc).map(\.name) == ["moonlight"])
    }

    @Test func aCloudTrackOrRecordIsNotAStarter() {
        let own = mine[0]
        #expect(!StarterTracks.isStarter(own.tracks[0].rpmId))
        #expect(!StarterTracks.isStarter(own))
        #expect(!StarterTracks.isStarterKey(own.key))
        #expect(StarterTracks.record(of: own) == nil)
        #expect(StarterTracks.record(of: own.tracks[0].rpmId) == nil)

        let mixed = CloudAlbum(key: "k", album: "Mixed", artist: "Act",
                               tracks: own.tracks + [StarterTracks.tracks[0]])
        #expect(!StarterTracks.isStarter(mixed))
        #expect(!StarterTracks.isStarter(CloudAlbum(key: "k", album: "", artist: "", tracks: [])))
    }

    @Test func theStarterShelfIsOnlyStarterRecords() {
        #expect(StarterTracks.isStarterShelf(starters))
        #expect(!StarterTracks.isStarterShelf(mine))
        #expect(!StarterTracks.isStarterShelf(mine + starters))
        #expect(!StarterTracks.isStarterShelf([]))
    }
}
