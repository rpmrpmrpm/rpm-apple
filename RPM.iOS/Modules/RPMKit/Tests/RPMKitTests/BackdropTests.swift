import Testing
import Foundation
@testable import RPMKit

/// Which picture the app stands on, given what the listener chose and what their account may have.
///
/// The desktop's `Backdrop.EffectiveId` answers the same question and the two must not disagree: a
/// row of tiles that lit gold while the default was on the screen would be the app saying it had
/// done something it had not.
struct BackdropTests {
    @Test func nothingStoredIsTheAppsOwnGround() {
        #expect(Backdrop.standing(stored: "", gold: false) == .standard)
    }

    @Test func aStoredChoiceStands() {
        #expect(Backdrop.standing(stored: "pegasus", gold: false) == .pegasus)
        #expect(Backdrop.standing(stored: "vinyl", gold: false) == .vinyl)
        #expect(Backdrop.standing(stored: "sheet-music", gold: false) == .sheetMusic)
    }

    /// A stored "night" is an id from an earlier version. The vinyl takes the place of that table,
    /// so it stands on the vinyl, and no tile is named night.
    @Test func aStoredNightIsTheVinyl() {
        #expect(Backdrop.standing(stored: Backdrop.formerNight, gold: false) == .vinyl)
        #expect(Backdrop.standing(stored: Backdrop.formerNight, gold: true) == .vinyl)
        #expect(!Backdrop.Choice.allCases.map(\.rawValue).contains(Backdrop.formerNight))
    }

    /// The phone stores what the desktop stores (`Backdrop.SheetMusicId`), so the id is spelled the
    /// same on both heads.
    @Test func theSheetMusicIsStoredAsTheDesktopStoresIt() {
        #expect(Backdrop.Choice.sheetMusic.rawValue == "sheet-music")
        #expect(Backdrop.Choice.sheetMusic.nameKey == "Settings_BackgroundSheetMusic")
        #expect(!Backdrop.Choice.sheetMusic.isSupporters)
    }

    /// The blue vinyl is a free choice, and a supporter can stand on it as well as on the gold.
    @Test func theVinylStandsForEveryAccount() {
        #expect(Backdrop.standing(stored: "vinyl", gold: true) == .vinyl)
        #expect(Backdrop.standing(stored: "vinyl", gold: false) == .vinyl)
    }

    /// A stored "rpamp" is an id from an earlier version. That ground is now the default, so it
    /// stands as the default and lights the Default tile.
    @Test func aStoredRPaMpIsTheDefault() {
        #expect(Backdrop.standing(stored: Backdrop.formerRPaMp, gold: false) == .standard)
        #expect(Backdrop.standing(stored: Backdrop.formerRPaMp, gold: true) == .standard)
        #expect(!Backdrop.Choice.allCases.map(\.rawValue).contains(Backdrop.formerRPaMp))
    }

    /// A settings file from a later version should leave the app lit, not blank.
    @Test func aChoiceThisVersionDoesNotKnowIsTheAppsOwnGround() {
        #expect(Backdrop.standing(stored: "aurora", gold: false) == .standard)
    }

    @Test func aSupporterMayStandOnTheGoldOne() {
        #expect(Backdrop.standing(stored: "gold", gold: true) == .gold)
    }

    /// Support that has run out takes the gold down and leaves the same picture on the blue
    /// vinyl. It does not throw the choice away either: the stored id is left alone, so support
    /// that comes back puts the gold up again without anybody having to remember it.
    @Test func goldAskedForByAnAccountThatIsNotASupporterIsTheBlueVinyl() {
        #expect(Backdrop.standing(stored: "gold", gold: false) == .vinyl)
    }

    /// Which is why this answers what is STANDING rather than writing anything down.
    @Test func whatIsStoredIsNotChangedByAskingWhatStands() {
        let stored = "gold"

        _ = Backdrop.standing(stored: stored, gold: false)

        #expect(stored == "gold")
    }

    @Test func everyChoiceHasItsOwnId() {
        let ids = Backdrop.Choice.allCases.map(\.rawValue)

        #expect(Set(ids).count == ids.count)
        #expect(Backdrop.Choice.standard.rawValue.isEmpty)
    }

    /// The row of tiles shows the supporter's one to everybody: a backdrop nobody can see is a
    /// backdrop nobody knows to want.
    @Test func onlyTheGoldOneIsASupportersToOffer() {
        #expect(Backdrop.Choice.gold.isSupporters)
        #expect(Backdrop.Choice.allCases.filter(\.isSupporters) == [.gold])
    }
}
