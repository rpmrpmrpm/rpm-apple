import Foundation

/// How much of something there has to be before a screen is worth drawing, and how much there is.
///
/// This is a port of `RPM.Core/Library/FeatureGate.cs`, without its `GateNeed`. On this
/// platform the only gate is the home screen's, and a need that nothing asks about is a
/// case nobody can read.
///
/// **It does not know the threshold.** ``HomeGate/leastAlbums`` is passed in, because a
/// gate that chose its own thresholds would hold a second opinion about them.
public struct FeatureGate: Sendable, Equatable {
    /// How much there is now.
    public let have: Int
    /// How much there must be. Zero or less is a gate that is always open.
    public let want: Int

    public init(have: Int, want: Int) {
        self.have = have; self.want = want
    }

    /// Whether the screen may draw.
    public var open: Bool { have >= want }

    /// How much is still missing. Never negative. The sentence reads "12 albums to go", and
    /// a gate that is already open has nothing to go, not a negative amount.
    public var toGo: Int { max(0, want - have) }

    /// How far along, from zero to one, for a progress bar. The value is clamped at both
    /// ends. A gate that wants nothing reads as finished, rather than dividing by zero.
    /// A gate past its threshold does not draw a bar that overflows its track.
    public var fraction: Double {
        want <= 0 ? 1 : min(1, max(0, Double(have) / Double(want)))
    }
}

/// The home screen's gate.
public enum HomeGate {
    /// The fewest albums the home screen is worth drawing over.
    ///
    /// This is read from ``HomeShelf/rowLength``, which is twenty. With fewer than twenty
    /// albums, the Recently added row is the whole collection in a different order. The
    /// suggestions row can then only offer records that are already on the screen above it.
    public static let leastAlbums = HomeShelf.rowLength

    public static func of(albums: Int) -> FeatureGate {
        FeatureGate(have: albums, want: leastAlbums)
    }
}
