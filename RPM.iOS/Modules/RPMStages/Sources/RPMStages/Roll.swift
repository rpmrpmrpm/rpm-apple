import Foundation

/// A random source that can be replayed.
///
/// Swift's own generator cannot be seeded, and two of the looks need a seed: sand is
/// thrown on the plate once and never re-thrown, so the plate should look the same every
/// time the app starts, and a test that says "this figure forms" needs the same throw on
/// every run.
///
/// This is SplitMix64: eight lines, no state to warm up, and it passes the statistical
/// tests that matter for a picture. It is not for anything that has to be unguessable.
public struct Roll: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15

        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB

        return z ^ (z >> 31)
    }

    /// A value from 0 up to (not including) 1, which is the range every use here needs.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A value from -0.5 to 0.5: a throw with no direction of its own.
    public mutating func nudge() -> Float { Float(unit() - 0.5) }
}
