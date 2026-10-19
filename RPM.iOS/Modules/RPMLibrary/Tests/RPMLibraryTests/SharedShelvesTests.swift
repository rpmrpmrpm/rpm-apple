import Foundation
import Testing
import RPMKit
@testable import RPMLibrary

/// Which collections the library tab offers. The desktop (C#) has no tests for this, so these tests
/// follow the behaviour its code comments describe.

private func share(from owner: String) -> CloudShare {
    // The name on a received share is the grantee's name, which is the user's own. It is set to a
    // wrong-looking value on purpose: a row that used it would name the reader as the owner.
    CloudShare(ownerId: owner, granteeId: "me", granteeName: "Me", createdAt: 0)
}

private func rows(_ received: [CloudShare], faces: [String: PeerFace] = [:],
                  viewing: CloudShelf = .own, own: PeerFace = .nobody) -> [ShelfRow] {
    SharedShelves.rows(received: received, faces: faces, viewing: viewing,
                       ownName: "Your library", unknownName: "Shared library", ownFace: own)
}

@Test func theUsersOwnComesFirstAndIsOpenByDefault() {
    let made = rows([])

    #expect(made.count == 1)
    #expect(made[0].isOwn)
    #expect(made[0].name == "Your library")
    #expect(made[0].isOpen)
}

@Test func aSharedCollectionIsNamedByItsOwnersProfile() {
    let made = rows([share(from: "them")], faces: ["them": PeerFace(displayName: "Anna")])

    #expect(made.map(\.name) == ["Your library", "Anna"])
    #expect(made[1].shelf.ownerId == "them")
}

/// The share's name is the grantee's, so a row that used it would name the reader as the owner.
@Test func theNameOnTheShareIsNotUsed() {
    #expect(!rows([share(from: "them")]).contains { $0.name == "Me" })
}

/// An owner who has never set a profile name gets a generic name. The account id is never shown as a name.
@Test func anOwnerWithNoProfileIsCalledSomethingRatherThanNothing() {
    #expect(rows([share(from: "them")]).map(\.name) == ["Your library", "Shared library"])
}

@Test func theCollectionOnScreenIsTheOneMarkedOpen() {
    let made = rows([share(from: "them")], viewing: .of("them"))

    #expect(!made[0].isOpen)
    #expect(made[1].isOpen)
}

/// **Easy to forget.** The share may be revoked while someone is viewing it, or the list may not be
/// loaded yet on this launch. In both cases the row must stay, or the user has no way out of the shelf
/// they are viewing.
@Test func aCollectionSomebodyIsStandingInIsOnTheListEvenWhenTheShareHasGone() {
    let made = rows([], viewing: .of("gone"))

    #expect(made.count == 2)
    #expect(made[1].shelf.ownerId == "gone")
    #expect(made[1].isOpen)
}

@Test func aCollectionOnScreenIsNotListedTwice() {
    let made = rows([share(from: "them")], viewing: .of("them"))

    #expect(made.count == 2)
}

/// The initial a tile shows when the owner has no picture.
@Test func aRowFallsBackToTheInitialOfWhoeverItIs() {
    let made = rows([share(from: "them")], faces: ["them": PeerFace(displayName: "anna")])

    #expect(made[1].initial == "A")
}

@Test func aRowWithNothingToInitialiseSaysNothing() {
    let made = SharedShelves.rows(received: [share(from: "x")], faces: [:], viewing: .own,
                                  ownName: "Yours", unknownName: "\u{2014}", ownFace: .nobody)
    #expect(made[1].initial == "")
}

// ── the tile on your own row ──

/// The picture the user set in the settings, shown on the user's own row.
@Test func theOwnRowWearsThisAccountsPicture() {
    let mine = URL(string: "https://api.rpmrpmrpm.com/profiles/me/avatar?v=7")!
    let made = rows([], own: PeerFace(displayName: "Giovanni", avatar: mine))

    #expect(made[0].face.avatar == mine)

    // The tile shows the user's picture, but the name under it is still the collection's name.
    #expect(made[0].name == "Your library")
}

/// A name is not a picture. Other people without a picture are shown by their initial. A "Y" for
/// "Your library" would look like a person's initial, so the user's own row shows a house icon instead.
@Test func theOwnRowNeverFallsBackToALetter() {
    #expect(rows([], own: PeerFace(displayName: "Giovanni")).first?.initial == "")
    #expect(rows([]).first?.initial == "")
}

/// The supporter mark identifies other people. It is not shown on the user's own row.
@Test func theOwnRowNeverWearsTheSupporterMark() {
    let made = rows([share(from: "them")],
                    faces: ["them": PeerFace(displayName: "Anna", supporter: true)],
                    own: PeerFace(displayName: "Giovanni", supporter: true))

    #expect(!made[0].wearsMark)
    #expect(made[1].wearsMark)
}
