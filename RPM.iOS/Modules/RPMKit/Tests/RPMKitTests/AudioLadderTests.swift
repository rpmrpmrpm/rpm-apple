import Testing
@testable import RPMKit

/// The rule is ported from the desktop app (.NET), which has no tests for it. The part
/// worth holding is the cap: what is offered and what arrives must not disagree.

@Test func aRateOnTheLadderIsServedAsItIs() {
    for rate in AudioLadder.rates {
        #expect(AudioLadder.serve(rate, mayHaveOriginal: true) == rate)
    }
}

/// Down, never up. Rounding up would spend data nobody agreed to.
@Test(arguments: [(200, 192), (321, 320), (127, 96), (1000, 320)])
func aRateBetweenRungsComesDownToTheOneBelow(asked: (Int, Int)) {
    #expect(AudioLadder.serve(asked.0, mayHaveOriginal: true) == asked.1)
}

/// Below the bottom rung there is nowhere further down to go.
@Test func aRateUnderTheBottomRungIsTheBottomRung() {
    #expect(AudioLadder.serve(1, mayHaveOriginal: true) == 96)
}

@Test func aSupporterAskingForTheOriginalGetsIt() {
    #expect(AudioLadder.serve(AudioLadder.original, mayHaveOriginal: true) == AudioLadder.original)
}

/// **The cap.** A free account is served its one rung whatever it asks for, the
/// original included.
@Test(arguments: [0, 96, 192, 320, 9000])
func aFreeAccountIsCappedWhateverItAsksFor(asked: Int) {
    let served = AudioLadder.serve(asked, mayHaveOriginal: false)
    #expect(served == 128 || served == 96, "served \(served) for \(asked)")
    #expect(served != AudioLadder.original)
}

@Test func onlyTheRungsAreOnTheLadder() {
    #expect(AudioLadder.isOnTheLadder(320))
    #expect(!AudioLadder.isOnTheLadder(0), "the original is not a rendition")
    #expect(!AudioLadder.isOnTheLadder(160))
}

// ── what a chooser offers ──

/// The original first: it is what somebody who has thought about it wants.
@Test func theWholeLadderLeadsWithTheOriginal() {
    #expect(AudioLadder.RateOffer.whole.rungs.first == AudioLadder.original)
    #expect(!AudioLadder.RateOffer.whole.capped)
}

/// Listing the others greyed would be a longer way of saying the same thing.
@Test func aFreeAccountIsOfferedOneRung() {
    #expect(AudioLadder.RateOffer.free.rungs == [128])
    #expect(AudioLadder.RateOffer.free.capped)
}

/// Telling somebody they are on the free plan because a request timed out is the
/// worse of the two mistakes.
@Test func anAccountWhosePlanIsNotKnownIsOfferedEverything() {
    #expect(AudioLadder.RateOffer.unread == AudioLadder.RateOffer.whole)
}

/// A supporter's 320, read back after their support lapsed, is not on the offer any
/// more. It reads as the first rung rather than as an index off the end.
@Test func aRateThatIsNotOnTheOfferReadsAsTheFirstRung() {
    #expect(AudioLadder.RateOffer.free.indexOf(320) == 0)
    #expect(AudioLadder.RateOffer.free.settles(on: 320) == 128)
    #expect(AudioLadder.RateOffer.whole.settles(on: 320) == 320)
}

/// **What the whole type is for**: what is offered and what arrives agree.
@Test func whatAnOfferListsIsWhatItServes() {
    for offer in [AudioLadder.RateOffer.whole, .free] {
        for rung in offer.rungs {
            #expect(offer.serves(rung) == rung,
                    "offered \(rung) and serves \(offer.serves(rung))")
        }
    }
}

// ── where the phone is ──

@Test func theWifiRateIsAskedForOnAFreeNetwork() {
    let settled = AudioLadder.RateOffer.whole.settles(
        onWifi: AudioLadder.original, onCellular: 128, reach: .freely)

    #expect(settled == AudioLadder.original)
}

@Test func theCellularRateIsAskedForOnOneThatCosts() {
    let cellular = Reach(isOnline: true, costsData: true, isConstrained: false)
    let settled = AudioLadder.RateOffer.whole.settles(
        onWifi: AudioLadder.original, onCellular: 128, reach: cellular)

    #expect(settled == 128)
}

/// The arithmetic trap: the original is zero, so `min(chosen, 128)` lets through the
/// one rate rationing exists to prevent.
@Test func lowDataModeRationsTheOriginalRatherThanLettingItThrough() {
    let rationed = Reach(isOnline: true, costsData: true, isConstrained: true)
    let settled = AudioLadder.RateOffer.whole.settles(
        onWifi: AudioLadder.original, onCellular: AudioLadder.original, reach: rationed)

    #expect(settled == AudioLadder.frugal)
}

@Test func lowDataModeCapsARateThatIsAlreadyOnTheLadder() {
    let rationed = Reach(isOnline: true, costsData: true, isConstrained: true)

    #expect(AudioLadder.RateOffer.whole.settles(
        onWifi: 320, onCellular: 320, reach: rationed) == AudioLadder.frugal)

    // Below the cap already: rationing takes nothing away that was not being spent.
    #expect(AudioLadder.RateOffer.whole.settles(
        onWifi: 96, onCellular: 96, reach: rationed) == 96)
}

/// Rationing does not un-cap a free account, and a free account's one rung survives it.
@Test func lowDataModeAndAFreeAccountAgree() {
    let rationed = Reach(isOnline: true, costsData: true, isConstrained: true)
    let settled = AudioLadder.RateOffer.free.settles(
        onWifi: 320, onCellular: 320, reach: rationed)

    #expect(settled == AudioLadder.freeKilobits)
}
