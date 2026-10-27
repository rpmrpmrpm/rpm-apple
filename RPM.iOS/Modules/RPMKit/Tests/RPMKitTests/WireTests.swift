import Testing
import Foundation
@testable import RPMKit

// ── playlists ──

/// `folder` is absent on a playlist written without folders, and
/// "no field" and "top of the tree" are the same answer. Reading through
/// `folderChain` rather than the raw optional is what keeps a nil from becoming
/// a playlist that vanishes out of the tree.
@Test func playlistWithoutAFolderIsAtTheTop() throws {
    let lists = try fixture("cloud-playlists", as: CloudPlaylistsResponse.self)
    let old = try #require(lists.playlists.first { $0.playlistId == "pl_legacy" })
    #expect(old.folder == nil)
    #expect(old.folderChain == [])
}

/// A folder may be called anything a person can type, including something with a
/// slash in it, so the chain travels as segments and never as one path string.
@Test func folderChainKeepsSegmentsThatContainSlashes() throws {
    let lists = try fixture("cloud-playlists", as: CloudPlaylistsResponse.self)
    let nested = try #require(lists.playlists.first { $0.playlistId == "pl_nested" })
    #expect(nested.folderChain == ["Sets", "AC/DC night"])
}

// ── quota ──

@Test func quotaFromAServerWithoutTheUnlimitedFieldIsNotUnlimited() throws {
    let quota = try fixture("cloud-quota", as: CloudQuota.self)
    #expect(quota.usedBytes == 12_000_000_000)
    #expect(quota.quotaBytes == 100_000_000_000)
    #expect(quota.unlimited == false)
    #expect(quota.supporter == false)
    #expect(quota.tester == false)
}

@Test func aTesterHasTheSupporterFeaturesACeilingAndNoMark() throws {
    let quota = try fixture("cloud-quota-tester", as: CloudQuota.self)
    #expect(quota.supporter)
    #expect(quota.tester)
    #expect(quota.unlimited == false)
    #expect(quota.quotaBytes == 107_374_182_400)
    #expect(quota.wearsMark == false)
}

@Test func aServerWithoutTheSupporterFieldTakesItFromUnlimited() throws {
    let data = Data(#"{"usedBytes":1,"quotaBytes":9223372036854775807,"fileCount":1,"unlimited":true}"#.utf8)
    let quota = try RPMJSON.decoder.decode(CloudQuota.self, from: data)
    #expect(quota.supporter)
    #expect(quota.tester == false)
    #expect(quota.wearsMark)
}

// ── sharing ──

@Test func sharesCarryBothDirections() throws {
    let shares = try fixture("cloud-shares", as: CloudShares.self)
    #expect(shares.granted.count == 1)
    #expect(shares.received.count == 1)
    #expect(shares.received[0].granteeName == "Placeholder Two")
}

/// An envelope, not a bare array. The live service answers `{"devices":[...]}`,
/// which is what this fixture is a capture of.
@Test func aDeviceThatHasNeverBeenSeenDecodes() throws {
    let devices = try fixture("cloud-devices", as: DevicesResponse.self).devices ?? []
    #expect(devices.count == 2)
    #expect(devices[1].lastSeenAt == 0)
}

// ── album marks ──

/// The envelope is `albums`, not `marks`. Named after what the store calls them,
/// because a key that decodes to nothing reports no error at all.
@Test func albumMarksArriveUnderAlbums() throws {
    let marks = try fixture("cloud-album-marks", as: CloudAlbumMarksResponse.self)
    #expect(marks.albums.count == 2)
    let first = try #require(marks.albums.first)
    #expect(first.favorite)
    #expect(first.updatedAt > 0)
    #expect(marks.albums[1].favorite == false)
    // Written without the classical mark: no answer, not "not classical".
    #expect(marks.albums.allSatisfy { $0.classical == nil })
    #expect(marks.owner == nil)
}

/// Captured from the API's own serializer. `classical` is null, not false, on a
/// record only favourited, and the listing says whose it is.
@Test func albumMarksCarryTheClassicalAnswer() throws {
    let marks = try fixture("cloud-album-marks-classical", as: CloudAlbumMarksResponse.self)
    #expect(marks.owner == "user-a")
    #expect(marks.albums[0].classical == true)
    #expect(marks.albums[0].favorite)
    #expect(marks.albums[1].classical == nil)
}

/// What a borrower is handed: the owner's classical answers, and no favourites.
@Test func aBorrowedShelfsMarksCarryNoFavourites() throws {
    let marks = try fixture("cloud-album-marks-borrowed", as: CloudAlbumMarksResponse.self)
    #expect(marks.owner == "user-a")
    #expect(marks.albums.count == 1)
    #expect(marks.albums[0].classical == true)
    #expect(marks.albums[0].favorite == false)
}

// ── album art index ──

/// The store answers this route with two different shapes. An older API
/// sends bare keys with no stamps, and a client that drew no
/// covers at all rather than stale ones would be the worse failure.
@Test func theArtIndexReadsTheStampedShape() throws {
    let index = try fixture("cloud-art-index", as: AlbumArtIndex.self)
    let covers = index.covers
    #expect(covers.count == 2)
    #expect(covers[0].albumKey == "talk talk|laughing stock")
    #expect(covers[0].updatedAt == 1_756_252_800)
}

/// Every cover cache is keyed on the stamp. Zero means the server did not say,
/// which reads as "no version known" rather than as "new": a cache that treats
/// it as new re-fetches every sleeve on every launch.
@Test func theArtIndexReadsTheOlderBareShapeAsUnstamped() throws {
    let index = try fixture("cloud-art-index-legacy", as: AlbumArtIndex.self)
    let covers = index.covers
    #expect(covers.count == 2)
    #expect(covers.allSatisfy { $0.updatedAt == 0 })
}
