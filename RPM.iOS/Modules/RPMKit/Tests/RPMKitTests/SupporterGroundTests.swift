import Foundation
import Testing
@testable import RPMKit

/// The rule is two sentences: a sign-in stands on what the cloud says, and every
/// later read only writes it down for next time. Every mistake either can make is
/// at one of the two ends: a free account wearing a supporter's ground, or a supporter
/// losing theirs because a request timed out. Both are here.
///
/// Each test gets its own store. `UserDefaults.standard` is the app's, and a test that
/// wrote to it would be a test that changed which picture somebody's phone opens on.

private func aStoreOfItsOwn(_ named: String) -> UserDefaults {
    let store = UserDefaults(suiteName: "SupporterGroundTests.\(named)")!
    store.removePersistentDomain(forName: "SupporterGroundTests.\(named)")
    return store
}

/// An account nobody has asked about yet is not a supporter. The safe direction: a
/// free account never sees the gold, and a supporter waits for the sign-in that says
/// so.
@Test func aStoreNobodyHasWrittenToOpensOnTheAppsOwnGround() {
    #expect(!SupporterGround.remembered(in: aStoreOfItsOwn(#function)))
}

@Test func whatTheCloudSaidIsWhatTheNextLaunchStandsOn() {
    let store = aStoreOfItsOwn(#function)

    SupporterGround.remember(isSupporter: true, in: store)
    #expect(SupporterGround.remembered(in: store))

    SupporterGround.remember(isSupporter: false, in: store)
    #expect(!SupporterGround.remembered(in: store))
}

/// The ground this launch is standing on is one value for the whole process, so these
/// two run one after another rather than beside each other, and each puts back what it
/// found.
@MainActor
@Suite(.serialized)
struct TheGroundUnderThisLaunch {
    /// **The whole point of remembering it.** Writing what the cloud has just said must
    /// not move the ground a screen is already being read on: that is the swap the
    /// remembering exists to prevent.
    @Test func rememberingDoesNotMoveTheGroundUnderThisLaunch() {
        let standing = SupporterGround.isGold

        SupporterGround.remember(isSupporter: !standing, in: aStoreOfItsOwn(#function))

        #expect(SupporterGround.isGold == standing)
    }

    /// **And the one moment it does move.** A supporter who signs in stands on the gold
    /// in that same launch, because the sign-in screen is what was on the screen and
    /// there is nothing to swap.
    @Test func aSignInStandsOnWhatTheCloudSaysStraightAway() {
        let standing = SupporterGround.isGold
        defer { SupporterGround.adopt(isSupporter: standing, in: aStoreOfItsOwn("putting it back")) }

        let store = aStoreOfItsOwn(#function)
        SupporterGround.adopt(isSupporter: !standing, in: store)

        #expect(SupporterGround.isGold == !standing)

        // And the next launch is told the same thing, so it opens where this one ended.
        #expect(SupporterGround.remembered(in: store) == !standing)
    }
}
