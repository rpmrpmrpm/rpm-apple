import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The generated lists as the home screen sees them. Lookups are by name, because a row on that
/// screen carries only a name.
///
/// There is one lookup for every caller. The screen needs the list to draw its picture, and the
/// shell needs it to open the list. Two lookups could disagree, and then a card would open a list
/// other than the one it shows.
struct HomeListsTests {
    private func set(_ name: String, id: String = "", origin: PlaylistOrigin = .generated,
                     shelf: CloudShelf = .own) -> PlaylistSet {
        PlaylistSet(id: id.isEmpty ? "p-" + name : id, name: name, tracks: [], missing: 0,
                    folder: [], stamp: 0, shelf: shelf, origin: origin)
    }

    @Test func aListIsFoundByTheNameTheScreenCarries() {
        let found = HomeLists.set(named: "Chill", in: [set("Adrenaline"), set("Chill")])

        #expect(found?.name == "Chill")
    }

    @Test func aNameNoListHasIsNotFound() {
        #expect(HomeLists.set(named: "Chill", in: [set("Adrenaline")]) == nil)
    }

    /// Two lists can have the same name, because they sit in different folders and the home screen
    /// shows only the name. The first one wins, so the card and the list it opens are the same.
    @Test func theFirstOfTwoListsSharingANameStands() {
        let found = HomeLists.set(named: "Chill",
                                  in: [set("Chill", id: "one"), set("Chill", id: "two")])

        #expect(found?.id == "one")
    }

    /// A generated list's id starts with a `\u{1}mood/` mark, which keeps it apart from a list somebody
    /// made. The picture is stored under the id without that mark.
    @Test func aGeneratedListsPictureIsAskedForUnderTheStoresOwnId() {
        let cut = set("Chill", id: "\u{1}mood/abc")

        #expect(cut.picture.id == "abc")
        #expect(cut.picture.shelf == .own)
    }

    @Test func aListSomebodyMadeKeepsItsOwnId() {
        let made = set("Chill", id: "abc", origin: .stored)

        #expect(made.picture.id == "abc")
    }

    /// The picture records whether the list is generated, because that decides whether it shows a
    /// built-in photo or the store's figure. A list the user made carries no cut.
    @Test func aGeneratedListsPictureCarriesItsCut() {
        let cut = GeneratedCut(kind: "Calm", genre: "Rock", decade: 0)
        let chill = PlaylistSet(id: "\u{1}mood/abc", name: "Slow Burn", tracks: [], missing: 0,
                                folder: [], stamp: 0, shelf: .own, origin: .generated, cut: cut)

        #expect(chill.picture.cut == cut)
        #expect(set("Road trip", origin: .stored).picture.cut == nil)
    }

    /// A set rebuilt with new tracks keeps its cut. `with(tracks:)` must keep it, or a generated list
    /// would lose its frame and photo.
    @Test func aSetWithNewTracksKeepsItsCut() {
        let cut = GeneratedCut(kind: "Decade", genre: nil, decade: 1980)
        let eighties = PlaylistSet(id: "\u{1}mood/x", name: "1980s", tracks: [], missing: 0,
                                   folder: [], stamp: 0, shelf: .own, origin: .generated, cut: cut)

        #expect(eighties.with(tracks: []).cut == cut)
    }

    // ── what the lists row offers ──

    /// On the user's own shelf the row shows only generated lists. The user's own playlists are on
    /// another tab.
    @Test func theOwnShelfOffersOnlyTheGeneratedLists() {
        let sets = [set("Chill"), set("Road trip", origin: .stored), set("Focus")]

        #expect(HomeLists.offered(sets, on: .own) == ["Chill", "Focus"])
    }

    /// On a borrowed shelf the lender's own playlists come after the generated ones, as on the desktop.
    @Test func aBorrowedShelfOffersTheLendersPlaylistsAfterTheGeneratedOnes() {
        let lender = CloudShelf.of("lender")
        let sets = [set("Road trip", origin: .stored, shelf: lender),
                    set("Chill", shelf: lender),
                    set("Sunday", origin: .stored, shelf: lender)]

        #expect(HomeLists.offered(sets, on: lender) == ["Chill", "Road trip", "Sunday"])
    }

    @Test func noMoreThanEightGeneratedListsAreOffered() {
        let sets = (1...10).map { set("List \($0)") }

        #expect(HomeLists.offered(sets, on: .own).count == HomeLists.generatedCount)
    }
}
