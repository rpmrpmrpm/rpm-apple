import Foundation

/// A run of bars across a given length: how many fit, which bands each reads, and how
/// tall it is allowed to stand.
///
/// Ported from `RPM.Core/Viz/SpectrumRun.cs`.
///
/// The desktop draws one bar per band because it has a whole landscape window to run
/// across. **A phone does not**: the run flanks the sleeve, in the margin on either side
/// of it, which is a couple of inches at most. A hundred and twenty-eight bars in that
/// space would be a solid block of ink, so the columns are however many fit at a legible
/// pitch, and each reads the bands it covers.
///
/// Pure, and kept apart from the drawing, because **it is the part that can be wrong
/// without looking wrong**: a fold that drops the last band or counts one twice gives a
/// run that is quietly not the music.
public struct SpectrumRun: Equatable, Sendable {
    /// The fewest columns worth drawing. Below this the run is not a spectrum but a row of
    /// blocks, so it is left out.
    public static let fewest = 3

    /// How many bars there are.
    public let columns: Int

    /// ...across how much room, so a caller can place them without keeping the figure it
    /// asked with.
    public let length: Float

    private init(columns: Int, length: Float) {
        self.columns = columns
        self.length = length
    }

    /// Whether there is room for a run at all.
    public var fits: Bool { columns >= Self.fewest }

    /// How wide one column is, gap included.
    public var pitch: Float { columns > 0 ? length / Float(columns) : 0 }

    /// The run that fits across `length` at about `pitch` a bar.
    ///
    /// **Never more columns than there are bands.** Two columns that read one band stand at
    /// the same height, which gives a picket-fence look that the desktop also avoids.
    public static func across(_ length: Float, pitch: Float,
                              bands: Int = RoomBands.bands) -> SpectrumRun {
        guard length > 0, pitch > 0, bands > 0 else { return SpectrumRun(columns: 0, length: 0) }

        return SpectrumRun(columns: max(0, min(Int(length / pitch), bands)), length: length)
    }

    /// The level of one column: the mean of every band it covers.
    ///
    /// **Every band belongs to exactly one column and no band is left out**, however
    /// awkwardly the two counts divide. The boundaries are worked out from the column
    /// index rather than by stepping a cursor, so the last column always ends on the last
    /// band.
    public func level(_ bands: [Float], at column: Int) -> Float {
        guard columns > 0, column >= 0, column < columns, !bands.isEmpty else { return 0 }

        let from = column * bands.count / columns
        var upto = (column + 1) * bands.count / columns
        if upto <= from { upto = from + 1 }
        if upto > bands.count { upto = bands.count }

        var sum: Float = 0
        for at in from..<upto { sum += bands[at] }
        return sum / Float(upto - from)
    }

    /// How much of its full reach a bar at `along` is given: **the run stands tallest
    /// where it leaves the sleeve and settles as it travels out to the rim.**
    ///
    /// Only the room that the reading is given changes; the reading itself is untouched, so
    /// a quiet band at the rim still reads at its own level, drawn shorter. `damp` is how
    /// much height is taken away at the rim and `bend` is the curve of that reduction. Above
    /// one, the reduction is small near the sleeve and steepens toward the rim, which gives
    /// a curve rather than a wedge.
    public static func damp(_ along: Float, by damp: Float, bend: Float) -> Float {
        1 - damp * pow(min(1, max(0, along)), bend)
    }
}
