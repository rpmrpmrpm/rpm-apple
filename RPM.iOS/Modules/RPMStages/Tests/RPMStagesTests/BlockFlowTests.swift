import Foundation
import Testing
@testable import RPMStages

/// The flight through the block field.
///
/// **The draw order is the thing to check.** The blocks are opaque and there is no depth
/// buffer, so a far block is kept from covering a near one only because the far rows are
/// emitted first. If the order is reversed, the field still looks like a field, but it looks
/// inside out and nothing on screen shows the fault.
@Suite("The block field")
struct BlockFlowTests {
    let rate = 44_100
    let n = 2048

    func music(_ level: Float = 0.6) -> [Float] {
        var roll = Roll(seed: 11)

        return (0..<n).map { _ in level * roll.nudge() * 2 }
    }

    /// How far a colour is from the navy everything fogs into.
    func lit(_ face: BlockFace) -> Float {
        let d = face.colour - BlockFlow.background

        return (d * d).sum().squareRoot()
    }

    // ── the field ──

    @Test func thereIsAFieldAndEveryCornerIsANumber() {
        let flow = BlockFlow(frameSize: n)
        flow.fill(3, widthOverHeight: 2.17)

        #expect(!flow.faces.isEmpty, "nothing came back")

        #expect(flow.faces.allSatisfy {
            [$0.a, $0.b, $0.c, $0.d].allSatisfy { $0.x.isFinite && $0.y.isFinite }
        })

        #expect(flow.faces.allSatisfy { $0.colour.min() >= 0 && $0.colour.max().isFinite })
    }

    /// **A cube shows three of its six faces at most.** A face pointing away is dropped where
    /// it is decided, not left for a rasteriser to cull, because nothing later in the pipeline
    /// culls.
    @Test func aBlockNeverShowsMoreThanHalfOfItself() {
        let flow = BlockFlow(frameSize: n)
        flow.fill(3, widthOverHeight: 2.17)

        #expect(flow.faces.count <= BlockFlow.columns * BlockFlow.rows * 3,
                "\(flow.faces.count) faces from \(BlockFlow.columns * BlockFlow.rows) blocks")
    }

    /// **Painter's order, far row first.** Depth shows as fog here, so the first faces emitted
    /// are the dimmest and the last are the brightest.
    @Test func theFarRowsAreDrawnFirst() {
        let flow = BlockFlow(frameSize: n)
        for i in 0..<40 { flow.listen(music(), now: Double(i) * 0.025) }
        flow.fill(3, widthOverHeight: 2.17)

        let all = flow.faces
        #expect(all.count > 60, "too few faces to say anything: \(all.count)")

        let firstTenth = all.prefix(all.count / 10).map(lit).reduce(0, +) / Float(all.count / 10)
        let lastTenth = all.suffix(all.count / 10).map(lit).reduce(0, +) / Float(all.count / 10)

        #expect(lastTenth > firstTenth * 1.5,
                "the field is being drawn inside out: \(firstTenth) first, \(lastTenth) last")
    }

    // ── the flight ──

    /// It flies with nothing playing, and the music adds to the speed instead of making the
    /// field jump forward.
    @Test func itFliesInSilenceAndFasterWithMusic() {
        let quiet = BlockFlow(frameSize: n)
        let loud = BlockFlow(frameSize: n)

        for i in 0..<40 {
            quiet.listen([], now: Double(i) * 0.025)
            loud.listen(music(), now: Double(i) * 0.025)
        }

        for _ in 0..<40 {
            quiet.advance(1.0 / 40)
            loud.advance(1.0 / 40)
        }

        #expect(quiet.flown > 0.5, "the flight stopped in silence: \(quiet.flown)")
        #expect(loud.flown > quiet.flown, "the music did not push the speed")
    }

    /// A frame that arrives a second late must not give the flight a second of travel: the
    /// field would jump past a whole row of blocks.
    @Test func aLateFrameDoesNotJumpTheField() {
        let flow = BlockFlow(frameSize: n)
        flow.advance(4)

        #expect(flow.flown < 0.2, "a four-second frame flew \(flow.flown)")
    }

    /// **The lattice is renumbered as the camera flies, not rebuilt.** After a short flight the
    /// picture is the same picture a little further on, not a different field.
    @Test func theFieldIsTheSameFieldOneFrameLater() {
        let flow = BlockFlow(frameSize: n)
        flow.fill(3, widthOverHeight: 2.17)
        let before = flow.faces.count

        flow.advance(1.0 / 60)
        flow.fill(3 + 1.0 / 60, widthOverHeight: 2.17)

        #expect(abs(flow.faces.count - before) < before / 5,
                "the field went from \(before) faces to \(flow.faces.count) in one frame")
    }

    // ── the light ──

    /// Fast attack, slow settle, like the sea's. It drives the light, the block size and the
    /// flight speed together, so a twitchy value would make the whole picture twitch.
    @Test func theSwellRisesQuicklyAndSettlesSlowly() {
        let flow = BlockFlow(frameSize: n)

        for i in 0..<20 { flow.listen(music(), now: Double(i) * 0.025) }
        let up = flow.swell
        #expect(up > 0.1, "the field never lit: \(up)")

        for i in 0..<40 { flow.listen([], now: 1 + Double(i) * 0.025) }

        #expect(flow.swell < up, "it did not settle")
        #expect(flow.swell > up * 0.6, "it cut rather than settled: \(up) to \(flow.swell)")
    }

    /// Loud music gives a brighter field. The lamp follows the swell, so this test shows that
    /// the look is lit by the track and does not only move with it.
    @Test func loudMusicLightsTheField() {
        func brightness(_ frame: [Float]) -> Float {
            let flow = BlockFlow(frameSize: n)
            for i in 0..<40 { flow.listen(frame, now: Double(i) * 0.025) }
            flow.fill(3, widthOverHeight: 2.17)

            return flow.faces.map(lit).reduce(0, +) / Float(max(1, flow.faces.count))
        }

        #expect(brightness(music(0.9)) > brightness([]),
                "the field is the same brightness whatever is playing")
    }
}
