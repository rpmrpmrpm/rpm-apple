import Foundation
import RPMKit

/// How much of the levelling is applied: whether a record plays at the same level as the
/// previous one, and what "the same level" is measured over.
///
/// Stored **by name** wherever it is saved. If it were stored as a number, inserting a mode in
/// the middle would silently change every saved choice to its neighbour.
public enum NormalizeMode: String, Codable, Sendable, CaseIterable {
    /// Every record plays at the level it was mastered at, with no levelling.
    case off

    /// The default. Each record is levelled as a whole, so the loud song and the quiet song keep
    /// the difference in level that the record's producer intended.
    case album

    /// Every track is levelled on its own. This suits a shuffled queue of unrelated songs, but it
    /// flattens a side that was built to rise and fall.
    case track
}

/// What is known about how loud something is.
public struct Level: Sendable, Equatable {
    /// Programme loudness in LUFS. Nil when it has not been measured.
    public let lufs: Double?

    /// Peak as a **linear amplitude**, where 1.0 is full scale. Nil when unknown. A boost is then
    /// applied without the peak protection it would otherwise have.
    public let truePeak: Double?

    public init(lufs: Double? = nil, truePeak: Double? = nil) {
        self.lufs = lufs; self.truePeak = truePeak
    }

    public static let unknown = Level()

    /// False for a track that has not been measured, and for one that could not be measured. A
    /// meter returns negative infinity for silence and for a file it could not read, and neither
    /// can be used to compute a gain.
    public var known: Bool {
        guard let lufs else { return false }
        return lufs.isFinite
    }

    /// The levels stored in a catalogue row. Zero means "not measured" in both fields, so zero is
    /// not used as a number here.
    public init(_ tags: CloudTrackTags?) {
        guard let tags else { self.init(); return }
        self.init(lufs: tags.hasLoudness ? tags.loudnessLufs : nil,
                  truePeak: tags.truePeak > 0 ? tags.truePeak : nil)
    }
}

/// Everything the decision needs beside the measurements themselves.
public struct NormalizeContext: Sendable, Equatable {
    public var mode: NormalizeMode

    /// Whether classical recordings are levelled too. False by default.
    public var includeClassical: Bool

    /// The listener's choice for this record: nil lets the other settings decide, and true or
    /// false decides it directly.
    public var albumOverride: Bool?

    /// Whether the listener has marked this record as classical. It is never detected
    /// automatically. The value is per source, so the engine's copy of the setting never holds
    /// it: ``SourceLoudness/gain(under:)`` sets it from the source.
    public var albumIsClassical: Bool

    /// Whether the record is played **as a record** and not as one song in a shuffled queue.
    public var inAlbumOrder: Bool

    public init(mode: NormalizeMode = .album, includeClassical: Bool = false,
                albumOverride: Bool? = nil, albumIsClassical: Bool = false,
                inAlbumOrder: Bool = true) {
        self.mode = mode
        self.includeClassical = includeClassical
        self.albumOverride = albumOverride
        self.albumIsClassical = albumIsClassical
        self.inAlbumOrder = inAlbumOrder
    }
}

/// Which measurement a gain came from, for code that needs to report it.
public enum NormalizeBasis: String, Sendable {
    case none, album, track
}

public struct NormalizeDecision: Sendable, Equatable {
    /// The gain to apply, in dB. Zero is used when levelling is off, when this record is
    /// excluded, and when the track has not been measured.
    public let gainDb: Double
    public let basis: NormalizeBasis

    public static let none = NormalizeDecision(gainDb: 0, basis: .none)

    public init(gainDb: Double, basis: NormalizeBasis) {
        self.gainDb = gainDb; self.basis = basis
    }

    /// The gain as a linear multiplier, for the audio pipeline.
    public var linear: Float { ReplayGain.linear(gainDb) }

    /// Whether this changes the sound. A gain below 0.01 dB is inaudible and not worth leaving
    /// the pipeline's bypass for.
    public var applies: Bool { abs(gainDb) >= 0.01 }

    public static func == (a: NormalizeDecision, b: NormalizeDecision) -> Bool {
        a.basis == b.basis && abs(a.gainDb - b.gainDb) < 1e-9
    }
}

/// Whether this record is levelled, what against, and by how much.
///
/// This is separate from the player and the settings screen because it contains the decisions,
/// and a wrong decision is not visible to the user.
public enum Normalization {
    /// The gain to play a track at.
    ///
    /// The settings are applied from the most specific to the least specific. The listener's
    /// choice for this one record wins over everything, including the classical rule. A listener
    /// who switches levelling on for a boxed set has given a more precise instruction than
    /// "leave classical alone". Next comes the classical rule, and last the global mode.
    ///
    /// Which measurement is used is a separate question from whether levelling is used. It depends
    /// on how the record is played, not on a setting. **Album gain is used in album order, and
    /// track gain on shuffle.** The quiet song on a record is meant to be quiet in its place, but
    /// between two other songs it is just a quiet song.
    ///
    /// - Parameter album: The record's measurement, where known. Album mode falls back to the
    ///   track's own measurement when it is not known, so a partly measured library still plays
    ///   evenly and does not wait until every record has been measured.
    public static func resolve(_ context: NormalizeContext, track: Level, album: Level,
                               target: Double = ReplayGain.referenceLufs) -> NormalizeDecision {
        guard isOn(context) else { return .none }

        if context.mode == .album, context.inAlbumOrder, album.known {
            return decide(album, .album, target)
        }

        return track.known ? decide(track, .track, target) : .none
    }

    /// Whether this record is levelled at all, before any measurement is checked.
    public static func isOn(_ context: NormalizeContext) -> Bool {
        // The listener's own choice for this record decides it, in either direction.
        if let told = context.albumOverride { return told }
        if context.mode == .off { return false }

        // A symphony's quiet movement is meant to be quiet, but a meter reads it as a record at
        // the wrong level. Album mode protects movements that share a folder. It does not help a
        // recital disc of four unrelated works, so this is a separate rule and not a mode.
        return context.includeClassical || !context.albumIsClassical
    }

    private static func decide(_ level: Level, _ basis: NormalizeBasis,
                               _ target: Double) -> NormalizeDecision {
        NormalizeDecision(
            gainDb: ReplayGain.of(lufs: level.lufs ?? 0, truePeak: level.truePeak ?? 0,
                                  target: target),
            basis: basis)
    }
}

/// What one source in the engine is levelled from: its own measurement, its record's
/// measurement, and whether it was handed over as part of a record played in order.
///
/// These values are fixed when the source is handed to the engine, because that is when the queue
/// it came from is known. The engine runs ahead of what is heard (a whole track, with gapless),
/// so the queue can change before this source plays. The source still plays at the gain for the
/// queue it was chosen from. The desktop does the same.
///
/// The listener's setting is not stored here. The engine holds it separately and reads it for
/// every block, so switching levelling off affects the record that is already playing.
///
/// The record's own properties are stored here, because they describe the record and not the
/// listener. The classical mark is one of them: a record that its owner marked as classical is
/// not levelled unless the setting also levels classical records. The album's own Always/Never
/// choice is not stored here, because it exists only in the desktop's local library.
public struct SourceLoudness: Sendable, Equatable {
    public let track: Level
    public let album: Level
    public let inAlbumOrder: Bool

    /// Whether the record's owner marked it as classical, at the time the source was handed
    /// over.
    public let albumIsClassical: Bool

    /// - Parameter albumIsClassical: **There is no default value.** A source built without this
    ///   answer would level every classical record, with no warning.
    public init(track: Level, album: Level, inAlbumOrder: Bool, albumIsClassical: Bool) {
        self.track = track
        self.album = album
        self.inAlbumOrder = inAlbumOrder
        self.albumIsClassical = albumIsClassical
    }

    /// Nothing measured: used for a station and for every test source. It plays at unity gain
    /// whatever the setting says.
    public static let unmeasured = SourceLoudness(track: .unknown, album: .unknown,
                                                  inAlbumOrder: false, albumIsClassical: false)

    /// The gain for this source under the listener's setting.
    public func gain(under setting: NormalizeContext) -> NormalizeDecision {
        var context = setting
        context.inAlbumOrder = inAlbumOrder
        context.albumIsClassical = albumIsClassical
        return Normalization.resolve(context, track: track, album: album)
    }
}
