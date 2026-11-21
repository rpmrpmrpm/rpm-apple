import Foundation
import AVFAudio

/// The ten-band equaliser of the desktop (RPM.Core/Audio/Equalizer.cs), ported number for number, as
/// the Android phone ports it: a cascade of RBJ peaking biquads per channel, then the pre-amp, applied
/// to float samples in place. The tests pin it to the desktop's own cases
/// (RPM.Core.Tests/EqualizerTests.cs).
///
/// The desktop class also has a bass and a treble shelf. Its player always sets them to 0 dB (they are
/// for vinyl and cassette transfers), so they are not ported.
///
/// Gains can be changed at any time with ``setGains(preamp:bands:)``. The new coefficients are used
/// from the next block, and the filter memory is kept, so the music does not restart or click.
///
/// A value, used by one thread: the pump that owns it (``EqStage``).
public struct Equalizer {
    /// The centre frequencies in Hz: the desktop's ten bands, which are Winamp's.
    public static let bands: [Double] = [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000]

    /// How far a band or the pre-amp may go, either way, in dB.
    public static let maxGain = 12.0

    /// About one octave per band.
    static let q = 1.0

    /// A band is used only while its centre is under this share of the sample rate (0.5 is the
    /// Nyquist limit).
    static let highestCentre = 0.45

    /// 7.1 surround is the most the engine is ever given.
    public static let maxChannels = 8

    /// The label under a band's fader: "60", "1K", "16K". The same as the desktop's; numbers, not
    /// words.
    public static func label(_ hz: Double) -> String {
        hz >= 1000 ? "\(Int(hz) / 1000)K" : "\(Int(hz))"
    }

    public let sampleRate: Double
    public let channels: Int

    // The coefficients of each band, shared by the channels.
    private var b0: [Double]
    private var b1: [Double]
    private var b2: [Double]
    private var a1: [Double]
    private var a2: [Double]

    // Transposed direct form II state, per band per channel: band `b` of channel `c` is at
    // `c * bands + b`.
    private var z1: [Double]
    private var z2: [Double]

    private var preampGain = 1.0

    /// True when every band and the pre-amp are at 0 dB. ``process(_:frames:channel:)`` then changes
    /// nothing.
    public private(set) var isBypassed = true

    /// An equaliser for `channels` channels at `sampleRate`, flat; nil for a rate under 8 kHz or a
    /// channel count the engine never uses.
    public init?(sampleRate: Double, channels: Int) {
        guard sampleRate >= 8000, (1...Self.maxChannels).contains(channels) else { return nil }
        self.sampleRate = sampleRate
        self.channels = channels
        let stages = Self.bands.count
        b0 = Array(repeating: 1, count: stages)
        b1 = Array(repeating: 0, count: stages)
        b2 = Array(repeating: 0, count: stages)
        a1 = Array(repeating: 0, count: stages)
        a2 = Array(repeating: 0, count: stages)
        z1 = Array(repeating: 0, count: stages * channels)
        z2 = Array(repeating: 0, count: stages * channels)
    }

    /// Sets the pre-amp and each band's gain, all in dB and each held within ``maxGain`` either way.
    /// A band not given is flat.
    public mutating func setGains(preamp: Double, bands gains: [Double]) {
        var flat = abs(preamp) < 0.01
        preampGain = pow(10, min(max(preamp, -Self.maxGain), Self.maxGain) / 20)
        for band in Self.bands.indices {
            let gain = band < gains.count ? min(max(gains[band], -Self.maxGain), Self.maxGain) : 0
            if abs(gain) >= 0.01 { flat = false }
            setPeaking(band, centre: Self.bands[band], gain: gain)
        }
        isBypassed = flat
    }

    /// RBJ audio-EQ-cookbook peaking filter.
    ///
    /// A band whose centre is near or above half the sample rate is left flat. The engine runs at
    /// 44.1 kHz, but the filter may be given a slower stream. There the top bands lie past the
    /// highest frequency the stream can carry, and the cookbook's formula would give a filter that is
    /// unstable or that never decays.
    private mutating func setPeaking(_ band: Int, centre: Double, gain: Double) {
        if centre >= sampleRate * Self.highestCentre || gain == 0 {
            b0[band] = 1; b1[band] = 0; b2[band] = 0; a1[band] = 0; a2[band] = 0
            return
        }
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * centre / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * Self.q)

        let a0 = 1 + alpha / a
        b0[band] = (1 + alpha * a) / a0
        b1[band] = (-2 * cosW) / a0
        b2[band] = (1 - alpha * a) / a0
        a1[band] = (-2 * cosW) / a0
        a2[band] = (1 - alpha / a) / a0
    }

    /// Clears the filter memory, so the end of the last audio does not carry into the next (a seek,
    /// a new track).
    public mutating func reset() {
        for i in z1.indices { z1[i] = 0; z2[i] = 0 }
    }

    /// Filters `frames` samples of channel `channel` in place. The result is held to full scale (-1
    /// to 1), as the desktop holds it: a boost the pre-amp does not make room for clips here, and not
    /// in the output.
    ///
    /// Each channel has its own filter memory, so the channels of one block can be filtered one
    /// after the other.
    public mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        guard !isBypassed, (0..<channels).contains(channel) else { return }
        let stages = Self.bands.count
        let base = channel * stages
        for i in 0..<frames {
            var x = Double(samples[i])
            for b in 0..<stages {
                let s = base + b
                let y = b0[b] * x + z1[s]
                z1[s] = b1[b] * x - a1[b] * y + z2[s]
                z2[s] = b2[b] * x - a2[b] * y
                x = y
            }
            x *= preampGain
            samples[i] = Float(min(max(x, -1), 1))
        }
    }

    /// Filters every channel of `buffer` in place, where it holds float samples one channel after
    /// another, as the engine's do.
    public mutating func process(_ buffer: AVAudioPCMBuffer) {
        guard !isBypassed, let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let count = min(Int(buffer.format.channelCount), channels)
        if buffer.format.isInterleaved {
            // Not a layout the engine uses; left as it is rather than filtered wrongly.
            return
        }
        for channel in 0..<count {
            process(data[channel], frames: frames, channel: channel)
        }
    }
}

/// One named curve: the desktop's presets (EqService.Presets), in its order, with its values. `gains`
/// holds one value per band, in ``Equalizer/bands`` order. `nameKey` is the string the name is read
/// from.
public struct EqPreset: Sendable, Equatable {
    public let nameKey: String
    public let gains: [Double]

    public static let all: [EqPreset] = [
        EqPreset(nameKey: "Eq_Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqPreset(nameKey: "Eq_Rock", gains: [5, 4, 2, 0, -1, 0, 2, 4, 5, 5]),
        EqPreset(nameKey: "Eq_Pop", gains: [-1, 2, 4, 5, 4, 2, 0, -1, -1, -2]),
        EqPreset(nameKey: "Eq_Jazz", gains: [4, 3, 1, 2, -1, -1, 0, 1, 3, 4]),
        EqPreset(nameKey: "Eq_Classical", gains: [5, 4, 3, 2, -1, -1, 0, 2, 3, 4]),
        EqPreset(nameKey: "Eq_BassBoost", gains: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
        EqPreset(nameKey: "Eq_Treble", gains: [0, 0, 0, 0, 0, 2, 4, 6, 7, 7]),
        EqPreset(nameKey: "Eq_Vocal", gains: [-2, -1, 1, 3, 4, 4, 3, 1, 0, -1]),
    ]
}

/// The equaliser settings for one set of speakers, as the desktop keeps them (EqProfile): on or off,
/// the pre-amp, and the ten band gains, all in dB. A value, so the pump can read one while the main
/// thread makes the next.
///
/// Off is a bypass for comparison, not a reset: the values are kept, and turning it on again brings
/// them back.
public struct EqCurve: Sendable, Equatable {
    public var on: Bool
    public private(set) var preamp: Double
    public private(set) var gains: [Double]

    /// A curve with `gains` held to the range and made ten long.
    public init(on: Bool, preamp: Double, gains: [Double]) {
        self.on = on
        self.preamp = Self.clamp(preamp)
        self.gains = Equalizer.bands.indices.map { $0 < gains.count ? Self.clamp(gains[$0]) : 0 }
    }

    /// A set of speakers seen for the first time: flat and off, the same as having no equaliser.
    public static let off = EqCurve(on: false, preamp: 0, gains: [])

    /// The same curve with one band moved, held to the range. A band that does not exist changes
    /// nothing.
    public func withBand(_ index: Int, _ db: Double) -> EqCurve {
        guard gains.indices.contains(index) else { return self }
        var next = self
        next.gains[index] = Self.clamp(db)
        return next
    }

    public func withPreamp(_ db: Double) -> EqCurve {
        var next = self
        next.preamp = Self.clamp(db)
        return next
    }

    /// The same curve switched on or off.
    public func turned(_ on: Bool) -> EqCurve {
        var next = self
        next.on = on
        return next
    }

    /// The preset's bands. The pre-amp and the switch stay as they are, as on the desktop.
    public func withPreset(_ preset: EqPreset) -> EqCurve {
        EqCurve(on: on, preamp: preamp, gains: preset.gains)
    }

    /// Flat, the pre-amp too. The switch stays where it was.
    public func flattened() -> EqCurve { EqCurve(on: on, preamp: 0, gains: []) }

    /// The preset whose bands this curve has, or nil. The pre-amp is not compared, as on the desktop.
    public var preset: EqPreset? {
        EqPreset.all.first { preset in
            gains.indices.allSatisfy { abs(gains[$0] - preset.gains[$0]) < 0.001 }
        }
    }

    /// As kept in the settings: on (1 or 0), the pre-amp, then the bands, separated by `;` and `,`.
    /// The same text as the Android phone keeps.
    public var stored: String {
        (on ? "1" : "0") + ";" + "\(preamp)" + ";" + gains.map { "\($0)" }.joined(separator: ",")
    }

    /// A curve read back from ``stored``. Anything that cannot be read is ``off``.
    public static func parse(_ text: String?) -> EqCurve {
        guard let parts = text?.split(separator: ";", omittingEmptySubsequences: false),
              parts.count == 3,
              let preamp = Double(parts[1]), preamp.isFinite
        else { return .off }
        var gains: [Double] = []
        for part in parts[2].split(separator: ",", omittingEmptySubsequences: false) {
            guard let gain = Double(part), gain.isFinite else { return .off }
            gains.append(gain)
        }
        guard gains.count == Equalizer.bands.count else { return .off }
        return EqCurve(on: parts[0] == "1", preamp: preamp, gains: gains)
    }

    private static func clamp(_ db: Double) -> Double {
        min(max(db, -Equalizer.maxGain), Equalizer.maxGain)
    }
}

/// The equaliser as the pump runs it: the filter, the curve it was last set to, and the source it
/// last filtered. One per run of the pump, so a start or a seek begins with clear filter memory.
struct EqStage {
    private var filter: Equalizer?
    private var applied: EqCurve?
    private var source: Int?
    private var wasOn = false

    /// Filters `buffer` of source `source` in place by `curve`, or leaves it alone while the curve is
    /// off or flat. A new source, a new format and a curve switched back on start from clear filter
    /// memory, so nothing of the audio before carries over.
    mutating func apply(_ curve: EqCurve, to buffer: AVAudioPCMBuffer, source id: Int) {
        let format = buffer.format
        if filter?.sampleRate != format.sampleRate || filter?.channels != Int(format.channelCount) {
            filter = Equalizer(sampleRate: format.sampleRate, channels: Int(format.channelCount))
            applied = nil
        }
        guard filter != nil else { return }

        if source != id {
            source = id
            filter?.reset()
        }
        guard curve.on else {
            wasOn = false
            return
        }
        if !wasOn {
            wasOn = true
            filter?.reset()
        }
        if applied != curve {
            filter?.setGains(preamp: curve.preamp, bands: curve.gains)
            applied = curve
        }
        filter?.process(buffer)
    }
}
