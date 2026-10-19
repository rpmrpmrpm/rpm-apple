import Foundation

/// How loud to play a track, given its measured loudness.
///
/// Ported from `RPM.Core/Analysis/ReplayGain.cs`. This is plain arithmetic, and a
/// mistake in it is silent: a badly levelled track plays at the wrong volume and
/// nothing reports an error.
public enum ReplayGain {
    /// The loudness that all tracks are levelled to, in LUFS. This is the ReplayGain 2.0
    /// reference. It matches the 89 dB reference of the first ReplayGain version, so a
    /// library partly tagged by an older tool gives the same result for every track.
    ///
    /// **It is not the streaming target.** Streaming services level to -14 LUFS, which
    /// suits a phone in a noisy place but removes headroom that a music collection has
    /// no reason to give up.
    public static let referenceLufs = -18.0

    /// How close to full scale a normalised track may come, in dBTP.
    ///
    /// Not zero. A converter reconstructs a curve between the samples, and that curve can
    /// go higher than the samples themselves. A margin of 1 dB is the usual allowance.
    public static let peakCeilingDb = -1.0

    /// The most a track may be turned up or down, in dB. A track that needs more than
    /// this is mastered so differently from the rest that moving it all the way would be
    /// more surprising than leaving it. On the quiet side it is usually a file that was
    /// measured wrongly.
    public static let maxGainDb = 15.0

    /// The gain that brings a measurement to the target, before checking what it does
    /// to the peaks.
    public static func gainDb(lufs: Double, target: Double = referenceLufs) -> Double {
        lufs.isFinite ? target - lufs : 0
    }

    /// The gain that is safe to apply: reduced so that the track's loudest peak stays
    /// under the ceiling, and limited to `maxGainDb` in both directions.
    ///
    /// **It only ever reduces a gain.** A track whose peaks are far below the ceiling is
    /// not raised to it. The ceiling is a limit, not a target, and raising a quiet
    /// recording to meet it would defeat the loudness measurement.
    ///
    /// - Parameter truePeak: the track's peak as a **linear amplitude**, where 1.0 is
    ///   full scale. It is not in dB. Zero or less means it was never measured, so
    ///   there is nothing to limit against.
    public static func clamp(_ gainDb: Double, truePeak: Double,
                             ceilingDb: Double = peakCeilingDb) -> Double {
        guard gainDb.isFinite else { return 0 }

        let capped = min(max(gainDb, -maxGainDb), maxGainDb)
        guard truePeak > 0, truePeak.isFinite else { return capped }

        // The room left between the peak and the ceiling. It is negative for a track
        // that is already over the ceiling, which is common for modern masters and is
        // exactly the case this limit is for.
        let headroom = ceilingDb - 20 * log10(truePeak)
        return Swift.min(capped, headroom)
    }

    /// Turns a measurement directly into the gain to apply. This is the one call a
    /// player needs.
    public static func of(lufs: Double, truePeak: Double,
                          target: Double = referenceLufs) -> Double {
        clamp(gainDb(lufs: lufs, target: target), truePeak: truePeak)
    }

    /// A gain in dB as a linear multiplier, which is what an audio pipeline needs.
    public static func linear(_ gainDb: Double) -> Float {
        gainDb.isFinite ? Float(pow(10, gainDb / 20)) : 1
    }

    /// An album's loudness from its tracks' loudness, in LUFS.
    ///
    /// It uses the mean of the tracks' mean squares, not the mean of their dB values,
    /// because **loudness does not average in decibels**: an album with one loud song
    /// and one quiet song is not as loud as the midpoint of the two numbers. Tracks are
    /// weighted by length, so a forty-second interlude counts for less than a
    /// ten-minute track. Tracks that were not measured are skipped.
    public static func albumLufs(_ tracks: [(lufs: Double, seconds: Double)]) -> Double {
        var sum = 0.0, weight = 0.0

        for track in tracks where track.lufs.isFinite {
            let length = track.seconds > 0 ? track.seconds : 1
            sum += pow(10, track.lufs / 10) * length
            weight += length
        }

        return weight > 0 ? 10 * log10(sum / weight) : -.infinity
    }
}
