import Testing
@testable import RPMKit

@Test func ownShelfSendsNoOwnerOnTheWire() {
    #expect(CloudShelf.own.isOwn)
    #expect(CloudShelf.own.owner == nil)
    #expect(CloudShelf.own.ownerId.isEmpty)
}

@Test func borrowedShelfCarriesTheOwner() {
    let shelf = CloudShelf.of("us-east-1:abc")
    #expect(!shelf.isOwn)
    #expect(shelf.owner == "us-east-1:abc")
}

/// A blank owner is the caller's own shelf under a stranger's name, which is the
/// exact failure the type exists to prevent. It is not an error to construct,
/// because a blank id can only come from a blank field; it collapses to `own`.
@Test func blankOwnerCollapsesToOwn() {
    #expect(CloudShelf.of("").isOwn)
    #expect(CloudShelf.of("   ").isOwn)
}

@Test func queryFragmentIsFirstOrSubsequentAsAsked() {
    #expect(CloudShelf.own.query(first: true) == "")
    #expect(CloudShelf.own.query(first: false) == "")
    #expect(CloudShelf.of("a b").query(first: true) == "?owner=a%20b")
    #expect(CloudShelf.of("a b").query(first: false) == "&owner=a%20b")
}
