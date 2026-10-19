import Testing
import Foundation
@testable import RPMKit

/// `cloud-list.json` is a CAPTURE. Two of its rows came off
/// `https://api.rpmrpmrpm.com/cloud/list` verbatim; the third is synthesised,
/// because the case that actually breaks a decoder is a row uploaded before the
/// catalogue existed, and no live account has one now.

@Test func decodesAFullyTaggedRow() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    let track = try #require(page.files.first)

    #expect(track.title == "Aniron (I Desire)")
    #expect(track.artist == "Enya")
    #expect(track.album == "The Very Best Of Enya")
    #expect(track.updatedAt > 0)
    #expect(track.tags?.trackNumber == 2)
    #expect(track.tags?.year == 2009)
    #expect(track.tags?.genre == "Celtic")
    #expect(track.tags?.sampleRate == 44100)
    #expect(track.tags?.bitsPerSample == 16)
}

/// An rpmId is a plain GUID with dashes. Nothing prefixes it, and a client that
/// pattern-matched one would reject every row in the store.
@Test func anRpmIdIsABareGuid() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    let id = try #require(page.files.first).rpmId
    #expect(UUID(uuidString: id) != nil, "\(id) is not a bare GUID")
}

/// The store sends five fields the C# record never declares: `hasLoudness`,
/// `hasFormat`, `isEmpty`, `hasPressing`, `hasWork`. They are computed
/// properties that System.Text.Json serialises anyway, so they are on the wire
/// whether or not anything wants them. Decoding must ignore them, and encoding
/// must not send them back: they are derived, and a server that took them at
/// face value would be told a lie by any client that got the derivation wrong.
@Test func computedFieldsOnTheWireAreIgnoredOnTheWayInAndNotSentBackOut() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    let tags = try #require(page.files.first?.tags)

    // Read, not echoed: the Swift works these out for itself.
    #expect(tags.hasLoudness)
    #expect(tags.hasFormat)

    let sent = String(data: try RPMJSON.encoder.encode(tags), encoding: .utf8) ?? ""
    for derived in ["hasLoudness", "hasFormat", "isEmpty", "hasPressing", "hasWork"] {
        #expect(!sent.contains(derived), "\(derived) was sent back to the store")
    }
}

/// The case that actually breaks: a row uploaded before the catalogue existed
/// carries no `tags` object at all, and every field on it is absent rather than
/// null. Decoding must not throw and must not invent zeroes that read as facts.
@Test func decodesARowFromBeforeTheCatalog() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    let bare = try #require(page.files.last)

    #expect(bare.tags == nil)
    #expect(bare.title == nil)
    #expect(bare.updatedAt == 0)
    #expect(bare.duration == .zero)
}

@Test func durationComesFromTagsAndIsZeroWhenUnknown() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    #expect(page.files[0].duration > .zero)
    #expect(page.files.last?.duration == .zero)
}

/// Zero is "not measured", not silence. A real reading is negative, since music
/// sits below full scale and a track at 0 LUFS would be a square wave. The
/// captured row reads -11.45.
@Test func loudnessIsKnownOnlyWhenNegative() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    #expect(page.files[0].tags?.hasLoudness == true)
    #expect((page.files[0].tags?.loudnessLufs ?? 0) < 0)
    #expect(page.files.last?.tags?.hasLoudness == nil)
}

/// True peak is dBTP and CAN be positive: a master that clips reads above zero.
/// It follows none of the "zero means unknown" rule the fields around it do.
@Test func truePeakMayBePositive() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    #expect((page.files[0].tags?.truePeak ?? -99) > 0)
}

/// Zero means "not known" and the store means it: this album carries a track
/// number but no track count and no disc numbering at all.
@Test func absentCountsComeBackAsZeroRatherThanAsOne() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    let tags = try #require(page.files.first?.tags)
    #expect(tags.trackNumber > 0)
    #expect(tags.trackCount == 0)
    #expect(tags.discNumber == 0)
    #expect(tags.discCount == 0)
    #expect(tags.albumArtist == nil)
}

/// The cursor is the id of the last row of the page, and `owner` is filled in
/// even for the caller's own shelf.
@Test func pageCarriesItsCursorAndItsOwner() throws {
    let page = try fixture("cloud-list", as: CloudListPage.self)
    #expect(page.cursor?.isEmpty == false)
    #expect(page.owner?.isEmpty == false)
}
