import Testing
@testable import RPMAudio

/// The output device changing under the engine, for example a Bluetooth device connecting while a
/// record plays. If this goes wrong, the record is opened again from its top and then jumps to the
/// second where it was, or it starts again on the phone's own speaker after the headphones went
/// away.
@Suite("The output device changes under the engine")
struct DeviceChangesTests {

    // Several changes in a row.

    @Test func aSingleChangeIsTheLatest() {
        var changes = DeviceChanges()
        let change = changes.happened()

        #expect(changes.isLatest(change))
    }

    /// A Bluetooth device can change the route and then the sample rate. Only the second change
    /// is answered, so the record is fed to the engine once.
    @Test func aBurstIsAnsweredOnceByItsLastChange() {
        var changes = DeviceChanges()
        let first = changes.happened()
        let second = changes.happened()

        #expect(!changes.isLatest(first))
        #expect(changes.isLatest(second))

        #expect(DeviceChanges.answer(latest: changes.isLatest(first), onThisPhone: true,
                                     starting: false, wantsToPlay: true, canCarryOn: true) == .nothing)
        #expect(DeviceChanges.answer(latest: changes.isLatest(second), onThisPhone: true,
                                     starting: false, wantsToPlay: true, canCarryOn: true) == .carryOnHere)
    }

    @Test func theWaitIsShort() {
        #expect(DeviceChanges.settle > .zero)
        #expect(DeviceChanges.settle <= .milliseconds(500))
    }

    // What is done once a change has settled.

    /// The case the tester reported: a record playing on the phone when a Bluetooth device
    /// connects goes on from where it was heard, from the feed it is already playing from.
    @Test func aPlayingRecordCarriesOnWhereItWasHeard() {
        #expect(DeviceChanges.answer(latest: true, onThisPhone: true, starting: false,
                                     wantsToPlay: true, canCarryOn: true) == .carryOnHere)
    }

    /// Only with no feed to move (a station, or a feed that has gone) is the record opened again.
    @Test func withNothingToCarryOnFromTheRecordIsOpenedAgain() {
        #expect(DeviceChanges.answer(latest: true, onThisPhone: true, starting: false,
                                     wantsToPlay: true, canCarryOn: false) == .openAgain)
    }

    /// A device going away pauses first. Nothing is fed, so no sound comes out of the phone's
    /// own speaker, and the next Play carries on.
    @Test func aPausedRecordWaitsForPlay() {
        #expect(DeviceChanges.answer(latest: true, onThisPhone: true, starting: false,
                                     wantsToPlay: false, canCarryOn: true) == .onPlay)
        #expect(DeviceChanges.answer(latest: true, onThisPhone: true, starting: false,
                                     wantsToPlay: false, canCarryOn: false) == .onPlay)
    }

    /// A start on its way puts its own source on the engine and starts it again. Feeding the old
    /// record as well would play it over the one that was chosen.
    @Test func aStartOnItsWayIsLeftAlone() {
        #expect(DeviceChanges.answer(latest: true, onThisPhone: true, starting: true,
                                     wantsToPlay: true, canCarryOn: true) == .nothing)
    }

    /// A cast has no local graph, and a station on AVFoundation does not use the engine.
    @Test func soundThatIsNotOnThisPhonesEngineIsLeftAlone() {
        #expect(DeviceChanges.answer(latest: true, onThisPhone: false, starting: false,
                                     wantsToPlay: true, canCarryOn: true) == .nothing)
        #expect(DeviceChanges.answer(latest: true, onThisPhone: false, starting: false,
                                     wantsToPlay: false, canCarryOn: true) == .nothing)
    }
}
