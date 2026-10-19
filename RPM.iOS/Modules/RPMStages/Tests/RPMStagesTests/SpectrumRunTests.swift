import Foundation
import Testing
@testable import RPMStages

/// The run's layout: how many bars fit, which bands each reads, how tall each may stand.
///
/// **A layout can be wrong without looking wrong.** A run that drops the last band or counts
/// one twice still draws a plausible row of bars. It is just not the music any more, and
/// nothing on screen shows that.
@Suite("A run of bars across a margin")
struct SpectrumRunTests {

    /// A run where every band is a different number, so a fold that loses one shows.
    func ramp(_ count: Int = RoomBands.bands) -> [Float] {
        (0..<count).map { Float($0) / Float(count - 1) }
    }

    // ── how many fit ──

    @Test func itFitsAsManyBarsAsTheMarginHasRoomFor() {
        #expect(SpectrumRun.across(140, pitch: 7).columns == 20)
        #expect(SpectrumRun.across(70, pitch: 7).columns == 10)
    }

    /// **Never more columns than bands.** Two columns reading one band stand at the same height
    /// and look like a picket fence, which the desktop app also avoids.
    @Test func itNeverDrawsMoreBarsThanThereAreBands() {
        let run = SpectrumRun.across(10_000, pitch: 1, bands: 32)

        #expect(run.columns == 32)
    }

    /// A margin that is too narrow gives a row of blocks, not a spectrum, so the run is left
    /// out.
    @Test(arguments: [0.0, 1.0, 13.0])
    func aMarginWithNoRoomInItDoesNotFit(width: Double) {
        #expect(!SpectrumRun.across(Float(width), pitch: 7).fits)
    }

    @Test func nothingIsDrawnForNonsense() {
        #expect(SpectrumRun.across(-40, pitch: 7).columns == 0)
        #expect(SpectrumRun.across(140, pitch: 0).columns == 0)
        #expect(SpectrumRun.across(140, pitch: 7, bands: 0).columns == 0)
    }

    // ── the fold ──

    /// **The main test.** Every band belongs to exactly one column and no band is left out,
    /// however unevenly the counts divide.
    @Test(arguments: [3, 7, 20, 31, 64, 127, 128])
    func everyBandIsReadByExactlyOneColumn(columns: Int) {
        let run = SpectrumRun.across(Float(columns) * 7, pitch: 7)
        #expect(run.columns == columns, "the fixture did not build the run it meant to")

        // Rebuild the boundaries the same way the fold does, and check they tile.
        var covered = [Int](repeating: 0, count: RoomBands.bands)

        for column in 0..<run.columns {
            let from = column * RoomBands.bands / run.columns
            var upto = (column + 1) * RoomBands.bands / run.columns
            if upto <= from { upto = from + 1 }
            if upto > RoomBands.bands { upto = RoomBands.bands }

            for at in from..<upto { covered[at] += 1 }
        }

        #expect(covered.allSatisfy { $0 == 1 },
                "\(covered.filter { $0 == 0 }.count) bands unread, \(covered.filter { $0 > 1 }.count) read twice")
    }

    /// The last column ends on the last band by construction, so the top of the spectrum cannot
    /// fall off the end of the run.
    ///
    /// The test lights **only the topmost band**, because a column reads the mean of what it
    /// covers: over a coarse run the last column spans a third of the spectrum and its mean is
    /// far below the top band's own level. What matters is that the column reads that band at
    /// all.
    @Test(arguments: [3, 9, 17, 50, 128])
    func theRunReachesTheTopOfTheSpectrum(columns: Int) {
        var bands = [Float](repeating: 0, count: RoomBands.bands)
        bands[RoomBands.bands - 1] = 1

        let run = SpectrumRun.across(Float(columns) * 7, pitch: 7)
        #expect(run.level(bands, at: run.columns - 1) > 0,
                "\(columns) columns and the top band was read by none of them")
    }

    /// ...and the same at the bottom, where a fold that starts one band in would lose the kick.
    @Test(arguments: [3, 9, 17, 50, 128])
    func theRunReachesTheBottomOfTheSpectrum(columns: Int) {
        var bands = [Float](repeating: 0, count: RoomBands.bands)
        bands[0] = 1

        let run = SpectrumRun.across(Float(columns) * 7, pitch: 7)
        #expect(run.level(bands, at: 0) > 0,
                "\(columns) columns and the bottom band was read by none of them")
    }

    /// A column reads the mean of what it covers, so a run with fewer bars has the same shape
    /// and is not a sample of every nth band.
    @Test func aColumnReadsTheMeanOfWhatItCovers() {
        let bands = ramp(8)
        let run = SpectrumRun.across(4 * 7, pitch: 7, bands: 8)

        // Four columns over eight bands: each reads two.
        #expect(run.columns == 4)
        #expect(abs(run.level(bands, at: 0) - (bands[0] + bands[1]) / 2) < 1e-6)
        #expect(abs(run.level(bands, at: 3) - (bands[6] + bands[7]) / 2) < 1e-6)
    }

    @Test func askingOutsideTheRunReadsNothing() {
        let run = SpectrumRun.across(140, pitch: 7)

        #expect(run.level(ramp(), at: -1) == 0)
        #expect(run.level(ramp(), at: run.columns) == 0)
        #expect(run.level([], at: 0) == 0)
    }

    // ── the reach ──

    /// **The run stands tallest where it leaves the sleeve and settles as it travels out.**
    /// Only the room given to a reading changes. The reading itself is unchanged, so a quiet
    /// band at the rim still reads at its own level, drawn shorter.
    @Test func aBarIsGivenLessRoomTheFurtherOutItIs() {
        let atSleeve = SpectrumRun.damp(0, by: 0.30, bend: 1.6)
        let midway = SpectrumRun.damp(0.5, by: 0.30, bend: 1.6)
        let atRim = SpectrumRun.damp(1, by: 0.30, bend: 1.6)

        #expect(atSleeve == 1, "the run should be at full height where it leaves the sleeve")
        #expect(abs(atRim - 0.70) < 1e-6, "the rim should have given back the damping")
        #expect(midway > atRim && midway < atSleeve)
    }

    /// **A curve, not a wedge.** Over a curve, the height taken away is small near the sleeve
    /// and steeper towards the rim. This makes a run that tapers, instead of one that looks cut
    /// off at an angle.
    @Test func theGivingBackIsACurveRatherThanAStraightLine() {
        let bent = SpectrumRun.damp(0.5, by: 0.30, bend: 1.6)
        let straight = SpectrumRun.damp(0.5, by: 0.30, bend: 1.0)

        #expect(bent > straight, "at the middle a bent run should still be taller: \(bent) against \(straight)")
    }

    @Test func theReachIsHeldInsideTheRun() {
        #expect(SpectrumRun.damp(-4, by: 0.30, bend: 1.6) == 1)
        #expect(abs(SpectrumRun.damp(9, by: 0.30, bend: 1.6) - 0.70) < 1e-6)
    }
}
