import Foundation
import CoreGraphics
import Testing
@testable import RPMArt

/// Which of an artist's photographs to show.
///
/// The look score is arithmetic, so it is tested as arithmetic. What the chooser does with it,
/// weighing where the face lands, how the picture looks and the cost of zooming, is tested on drawn
/// photographs. The question that matters is: does the better photograph win?
@Suite("Which photograph of the artist")
struct BackdropChooserTests {
    private let stage = ArtScene.forClearLeft(width: 852, height: 393, clearTop: 0,
                                              clearRight: 0.75, clearBottom: 0.62)

    /// A flat field of one colour, at a given brightness.
    private func flat(_ level: Double, edge: Int = 200) -> [UInt8] {
        [UInt8](repeating: UInt8(level * 255), count: edge * edge * 4)
    }

    // ── the look ──

    /// **Mid-dark wins.** A backdrop is drawn behind white words. A black bar gives no picture, and
    /// a glare makes the words hard to read. So the score peaks in between and falls to nothing at
    /// both ends.
    @Test func aBackdropWantsToBeMidDarkAndNotABlackBarOrAGlare() {
        func brightness(_ level: Double) -> Double {
            BackdropLook.score(BackdropLook.measure(
                rgba: flat(level), width: 200, height: 200,
                sourceWidth: 1920, sourceHeight: 1080))
        }

        #expect(brightness(0.45) > brightness(0.02))
        #expect(brightness(0.45) > brightness(0.98))
    }

    /// A photograph that cannot be measured scores in the middle, not at zero. It must not win
    /// because of a failure, and it must not be thrown out because of one.
    @Test func aPhotographThatCouldNotBeReadScoresMid() {
        let nothing = BackdropLook.measure(rgba: [], width: 0, height: 0,
                                           sourceWidth: 0, sourceHeight: 0)

        #expect(nothing.sourceMinDim == 0)
        #expect(BackdropLook.unmeasured == 0.5)
    }

    /// The short side stands in for how sharp a photograph looks when it is scaled up across a
    /// screen. Past a point, a larger photograph gains nothing.
    @Test func aBiggerPhotographIsWorthSomethingButNotForEver() {
        func sharp(_ short: Int) -> Double {
            BackdropLook.score(BackdropLook.measure(
                rgba: flat(0.45), width: 200, height: 200,
                sourceWidth: short * 2, sourceHeight: short))
        }

        #expect(sharp(1080) > sharp(240))
        #expect(sharp(2160) == sharp(720))
    }

    // ── where the face lands ──

    /// **The signal that matters most.** A face in the clear band scores full marks. The same face
    /// where the record covers it scores nothing, however good the photograph is.
    @Test func aFaceBehindTheRecordIsWorthNothing() {
        #expect(stage.facePosition(0.45) == 1)
        #expect(stage.facePosition(0.95) == 0)
        #expect(stage.facePosition(0.01) == 0)
    }

    /// The score ramps down rather than stepping. A face near the edge of what is shown is worth
    /// less than a face in the middle, but it is not thrown away.
    @Test func aFaceNearTheEdgeIsWorthLessThanOneInTheMiddle() {
        let middle = stage.facePosition(0.45)
        let near = stage.facePosition(0.70)

        #expect(near > 0)
        #expect(near < middle)
    }

    // ── the pick, remembered ──

    /// A photograph chosen by hand is kept, and the choice lasts across tracks, albums and app
    /// launches. Otherwise the score would undo the choice each time the record changes.
    @Test func aChoiceMadeByHandIsKept() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("picks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        var picks = BackdropPicks(file: file)
        let third = URL(string: "https://pictures.example/enya/2.jpg")!

        picks.remember(third, for: "Enya")

        // A new reader is used on purpose. The test checks what survives an app restart, not what
        // survives inside the same object.
        #expect(BackdropPicks(file: file).pick("enya") == third)
        #expect(BackdropPicks(file: file).pick("ENYA") == third)
        #expect(BackdropPicks(file: file).pick("Somebody Else") == nil)
    }

    @Test func aPickCanBeGivenBack() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("picks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        var picks = BackdropPicks(file: file)
        picks.remember(URL(string: "https://pictures.example/a.jpg")!, for: "Enya")
        picks.forget()

        #expect(BackdropPicks(file: file).pick("Enya") == nil)
    }
}
