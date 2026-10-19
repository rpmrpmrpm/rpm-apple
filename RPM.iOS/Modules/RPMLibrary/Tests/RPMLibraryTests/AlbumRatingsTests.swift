import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The stars given records on this device, by account and record. The Android TV's `AlbumRatings`.
@MainActor
struct AlbumRatingsTests {
    private func scratch() -> UserDefaults {
        let name = "rpm-ratings-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func record(_ name: String) -> CloudAlbum {
        var tags = CloudTrackTags()
        tags.albumArtist = "Talk Talk"
        let track = CloudTrack(rpmId: name + "-1", relativePath: "Talk Talk/\(name)/1.flac",
                               title: "One", artist: "Talk Talk", album: name, tags: tags)
        return CloudAlbum(key: "Talk Talk|\(name)", album: name, artist: "Talk Talk", tracks: [track])
    }

    @Test func aRecordNeverRatedHasNoStars() {
        let ratings = AlbumRatings(defaults: scratch())
        #expect(ratings.stars(of: record("Spirit of Eden"), account: "me") == 0)
    }

    @Test func aRatingIsKeptAndReadBack() {
        let defaults = scratch()
        let ratings = AlbumRatings(defaults: defaults)
        ratings.rate(record("Spirit of Eden"), stars: 4, account: "me")

        #expect(ratings.stars(of: record("Spirit of Eden"), account: "me") == 4)
        // Kept across launches: a new store over the same defaults reads it.
        #expect(AlbumRatings(defaults: defaults).stars(of: record("Spirit of Eden"), account: "me") == 4)
    }

    @Test func noStarsClearsTheRating() {
        let ratings = AlbumRatings(defaults: scratch())
        ratings.rate(record("Spirit of Eden"), stars: 3, account: "me")
        ratings.rate(record("Spirit of Eden"), stars: 0, account: "me")
        #expect(ratings.stars(of: record("Spirit of Eden"), account: "me") == 0)
    }

    @Test func aRatingIsAtMostFiveStars() {
        let ratings = AlbumRatings(defaults: scratch())
        ratings.rate(record("Spirit of Eden"), stars: 9, account: "me")
        #expect(ratings.stars(of: record("Spirit of Eden"), account: "me") == AlbumRatings.most)
    }

    /// Another account on this device has its own ratings, and a record its own.
    @Test func aRatingIsTheAccountsAndTheRecordsOwn() {
        let ratings = AlbumRatings(defaults: scratch())
        ratings.rate(record("Spirit of Eden"), stars: 5, account: "me")
        #expect(ratings.stars(of: record("Spirit of Eden"), account: "someone-else") == 0)
        #expect(ratings.stars(of: record("Laughing Stock"), account: "me") == 0)
    }
}
