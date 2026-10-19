import Foundation
import Testing
@testable import RPMStages

/// The three numbers the marched pictures are lit by.
@Suite("Bass, middle and air")
struct MarchBandsTests {
    let rate = 44_100
    let n = 2048

    /// A tone at exactly the middle of bin `k`, so the energy lands in one band.
    func tone(bin k: Int) -> [Float] {
        let hz = Double(k) * Double(rate) / Double(n)

        return (0..<n).map { Float(sin(2 * .pi * hz * Double($0) / Double(rate))) }
    }

    /// **The bands are where they say they are.** A picture lit by the wrong third of the
    /// spectrum still moves with the music, but it follows the wrong part, and the screen
    /// cannot show that.
    @Test func eachBandAnswersToItsOwnThirdOfTheSpectrum() {
        let low = MarchBands(frameSize: n)
        let middling = MarchBands(frameSize: n)
        let high = MarchBands(frameSize: n)

        low.listen(tone(bin: 10))
        middling.listen(tone(bin: 80))
        high.listen(tone(bin: 250))

        #expect(low.bass > low.middle && low.bass > low.air, "a low tone lit \(low.bass)/\(low.middle)/\(low.air)")
        #expect(middling.middle > middling.bass && middling.middle > middling.air)
        #expect(high.air > high.bass && high.air > high.middle)
    }

    /// **Fast up, slow down.** A hit arrives on the frame it happens and fades over the next
    /// few frames. If the light fell as fast as it rose, it would strobe on every snare.
    @Test func aHitArrivesAtOnceAndLeavesSlowly() {
        let bands = MarchBands(frameSize: n)

        bands.listen(tone(bin: 10))
        let hit = bands.bass
        #expect(hit > 0.1, "the hit did not arrive: \(hit)")

        bands.listen([])
        let after = bands.bass

        #expect(after < hit, "it did not leave")
        #expect(after > hit * 0.8, "it cut rather than left: \(hit) to \(after)")
    }

    /// Silence takes the light all the way down and does not leave a faint glow.
    @Test func silenceGoesDarkEventually() {
        let bands = MarchBands(frameSize: n)
        bands.listen(tone(bin: 10))

        for _ in 0..<400 { bands.listen([]) }

        #expect(bands.bass < 0.001 && bands.middle < 0.001 && bands.air < 0.001)
    }

    /// Every reading is a number a shader can be handed.
    @Test func everyReadingIsInRange() {
        let bands = MarchBands(frameSize: n)

        for level in [Float(0), 0.2, 1.0] {
            bands.listen((0..<n).map { _ in level })

            for reading in [bands.bass, bands.middle, bands.air] {
                #expect(reading >= 0 && reading <= 1, "\(reading)")
            }
        }
    }
}
