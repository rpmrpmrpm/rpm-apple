import Testing
@testable import RPMArt
import RPMLibrary

/// What goes behind a generated list's frame, in the same order as the desktop. The rule is kept in
/// one place, so every screen gives the same answer.
struct ListBehindTests {
    /// The five lists that stand on the room take that place before anything stored for them is used.
    @Test func theFiveRoomedListsStandOnTheRoom() {
        for kind in ["RightNow", "OnRepeat", "FavoriteTracks", "FirstListens", "LovedAndForgotten"] {
            #expect(ListBehind.of(GeneratedCut(kind: kind, genre: nil, decade: 0)) == .room, "\(kind)")
        }
    }

    /// A list with a shipped photograph shows it.
    @Test func aListWithAPhotographWearsIt() {
        let cut = GeneratedCut(kind: "Calm", genre: nil, decade: 0)
        #expect(PlaylistPhotos.has(cut))
        #expect(ListBehind.of(cut) == .photograph(cut))
    }

    /// A generated list with neither shows the picture the computer stored for it. So does a list
    /// somebody made.
    @Test func everythingElseShowsItsStoredPicture() {
        let bare = GeneratedCut(kind: "Calm", genre: nil, decade: 1990)
        #expect(!PlaylistPhotos.has(bare))
        #expect(ListBehind.of(bare) == .stored)
        #expect(ListBehind.of(nil) == .stored)
    }

    /// A kind this build does not know was made by a newer computer. It has no look, so it has no
    /// room, and it shows the stored picture.
    @Test func aKindThisBuildDoesNotKnowShowsItsStoredPicture() {
        #expect(ListBehind.of(GeneratedCut(kind: "SomethingNew", genre: nil, decade: 0)) == .stored)
    }
}
