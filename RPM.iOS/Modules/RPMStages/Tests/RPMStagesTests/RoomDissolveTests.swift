import Foundation
import Testing
@testable import RPMStages

/// A room changing colour.
///
/// **The dissolve is a function of the instant.** A stored palette advanced from inside the
/// analysis loop would be wrong without looking wrong: that loop does not turn until the engine
/// has named a sample rate, so a sheet opened on a paused track, or while the sound goes to a
/// speaker in another room, would keep the app's blue for a sleeve full of colour, and nothing
/// on screen would show that the arithmetic never ran. Derived from an instant, there is
/// nothing to forget to tick.
@Suite("The room changing colour")
struct RoomDissolveTests {

    /// Two palettes far enough apart that a channel says plainly where the travel is.
    let red = RoomPalette(ground: .init(0.1, 0, 0), tint: .init(1, 0, 0),
                          glow: .init(1, 0.2, 0), shade: .init(0.8, 0, 0.2))
    let green = RoomPalette(ground: .init(0, 0.1, 0), tint: .init(0, 1, 0),
                            glow: .init(0.2, 1, 0), shade: .init(0, 0.8, 0.2))

    func dissolve(at moment: Double = 10) -> RoomDissolve {
        RoomDissolve(from: red, to: green, at: moment)
    }

    // ── the two ends ──

    @Test func itStandsWhereItSetOffAtTheInstantItSetOff() {
        #expect(dissolve().read(10) == red)
    }

    @Test func itHasNotLeftBeforeItSetOff() {
        #expect(dissolve().read(9) == red)
    }

    @Test func itHasArrivedWellAfterwards() {
        let there = dissolve().read(20)
        #expect(abs(there.tint.x - green.tint.x) < 0.001)
        #expect(abs(there.tint.y - green.tint.y) < 0.001)
    }

    @Test func itIsPartWayAcrossInBetween() {
        let half = dissolve().read(10 + Double(log(2.0) / RoomDissolve.rate))
        #expect(abs(half.tint.y - 0.5) < 0.01)
        #expect(abs(half.tint.x - 0.5) < 0.01)
    }

    // ── the point of the whole type ──

    /// **Where it stands is a function of the instant and of nothing else**, so the picture
    /// does not depend on how often anything looks at it. A stored palette that advanced once
    /// per look would arrive for a room asked forty times a second and never arrive for a room
    /// that was not asked.
    @Test func whereItStandsDoesNotDependOnHowOftenItIsAsked() {
        let travel = dissolve()

        // Walked across in a hundred small looks, as a drawn frame would.
        for i in 1...100 { _ = travel.read(10 + Double(i) * 0.005) }

        // ...and then asked cold at an instant it was never asked at on the way.
        let k = 1 - exp(-Float(0.4) * RoomDissolve.rate)
        #expect(abs(travel.read(10.4).tint.y - k) < 1e-5)
    }

    // ── redirecting it ──

    @Test func aNewSleeveSetsOffFromWhereTheRoomActuallyStands() {
        let travel = dissolve()
        let standing = travel.read(10.2)

        let turned = travel.toward(red, at: 10.2)

        #expect(turned.from == standing)
        #expect(turned.to == red)
        #expect(turned.at == 10.2)
    }

    /// A view that hands over the same sleeve on every appearance must not restart the
    /// dissolve, or a record that changed a moment ago would begin its change again each time
    /// the sheet was shown.
    @Test func beingToldTheColoursItIsAlreadyHeadedForChangesNothing() {
        let travel = dissolve()
        #expect(travel.toward(green, at: 11) == travel)
    }

    @Test func aRoomToldNothingKeepsTheAppsOwnBlue() {
        #expect(RoomDissolve.still.read(100) == .fallback)
    }

    /// **The colours arrive with no measurement of any kind**, which is the case of a paused
    /// track and of a record playing in another room.
    @Test func itArrivesWithNothingHeardAtAll() {
        let sleeve = RoomPalette.from(tint: .init(0.55, 0.18, 0.10),
                                      glow: .init(0.95, 0.75, 0.20), shade: nil)

        let travel = RoomDissolve.still.toward(sleeve, at: 0)
        let there = travel.read(3)

        #expect(there != .fallback)
        #expect(abs(there.tint.x - sleeve.tint.x) < 0.001)
        #expect(abs(there.glow.y - sleeve.glow.y) < 0.001)
    }
}
