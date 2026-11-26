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
        guard let c = Self.peaking(centre: centre, gain: gain, sampleRate: sampleRate) else {
            b0[band] = 1; b1[band] = 0; b2[band] = 0; a1[band] = 0; a2[band] = 0
            return
        }
        b0[band] = c.b0; b1[band] = c.b1; b2[band] = c.b2; a1[band] = c.a1; a2[band] = c.a2
    }

    /// The coefficients of one peaking filter, already divided by a0.
    typealias Coefficients = (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double)

    /// The cookbook's coefficients for a band at `centre` Hz with `gain` dB, or nil where the band is
    /// left flat: no gain, or a centre too close to half the sample rate (see `setPeaking`).
    static func peaking(centre: Double, gain: Double, sampleRate: Double) -> Coefficients? {
        if centre >= sampleRate * highestCentre || gain == 0 { return nil }
        let a = pow(10, gain / 40)
        let w0 = 2 * Double.pi * centre / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * q)

        let a0 = 1 + alpha / a
        return (b0: (1 + alpha * a) / a0,
                b1: (-2 * cosW) / a0,
                b2: (1 - alpha * a) / a0,
                a1: (-2 * cosW) / a0,
                a2: (1 - alpha / a) / a0)
    }

    /// The highest gain of the ten bands together, in dB, without the pre-amp. It is read from the
    /// real response of the filters: at 256 frequencies from 20 Hz to 20 kHz, evenly spaced on a log
    /// scale, and at each band's centre. Neighbouring bands overlap, so two raised neighbours add up:
    /// all ten bands at +6 dB give about +15 dB, near 14 kHz where three bands are close together.
    ///
    /// A flat curve gives 0 dB, and a curve with only cuts gives 0 dB or less. `sampleRate` is the
    /// engine's rate (`StreamedPcm.engineFormat`) unless given.
    public static func peakGain(bands gains: [Double], sampleRate: Double = 44100) -> Double {
        let filters: [Coefficients] = Self.bands.indices.compactMap { band in
            let gain = band < gains.count ? min(max(gains[band], -maxGain), maxGain) : 0
            return peaking(centre: Self.bands[band], gain: gain, sampleRate: sampleRate)
        }
        guard !filters.isEmpty else { return 0 }

        let points = 256
        let lowest = 20.0
        let highest = 20000.0
        var frequencies = Self.bands
        for i in 0..<points {
            frequencies.append(lowest * pow(highest / lowest, Double(i) / Double(points - 1)))
        }

        var peak = -Double.infinity
        for hz in frequencies where hz < sampleRate / 2 {
            let w = 2 * Double.pi * hz / sampleRate
            let cos1 = cos(w), sin1 = sin(w), cos2 = cos(2 * w), sin2 = sin(2 * w)
            // The squared size of each filter's response at this frequency, multiplied together.
            var power = 1.0
            for f in filters {
                let numReal = f.b0 + f.b1 * cos1 + f.b2 * cos2
                let numImag = f.b1 * sin1 + f.b2 * sin2
                let denReal = 1 + f.a1 * cos1 + f.a2 * cos2
                let denImag = f.a1 * sin1 + f.a2 * sin2
                power *= (numReal * numReal + numImag * numImag) / (denReal * denReal + denImag * denImag)
            }
            peak = max(peak, 10 * log10(power))
        }
        return peak.isFinite ? peak : 0
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

    // ── room for the bands ──

    /// How far the bands together raise the loudest frequency, in dB, before the pre-amp
    /// (``Equalizer/peakGain(bands:sampleRate:)``).
    public var peak: Double { Equalizer.peakGain(bands: gains) }

    /// How far, in dB, the pre-amp and the peak together may go over 0 dB before the curve counts as
    /// clipping. It covers rounding in the response, so a band at +6 dB and the pre-amp at -6 dB do
    /// not count.
    static let clipAllowance = 0.05

    /// True while the curve is on and the pre-amp leaves too little room for the bands: the loudest
    /// sounds are pushed past full scale and clipped, which distorts. The equaliser card warns then.
    public var clips: Bool { on && preamp + peak > Self.clipAllowance }

    /// The same curve with the pre-amp lowered until the bands no longer clip. The pre-amp moves in
    /// whole dB, as the faders do, and only down. It stops at -12 dB, so a curve that needs more room
    /// than that still clips. A curve that is off, flat or has only cuts is returned as it is.
    public func withRoom() -> EqCurve {
        let most = Self.clipAllowance - peak
        guard on, preamp > most else { return self }
        return withPreamp(most.rounded(.down))
    }

    /// The curve to keep when the listener changes `before` into this one. When the switch is turned
    /// on, or the bands change while it is on (a fader, a preset, Flat), the pre-amp makes room
    /// (``withRoom()``). A change of the pre-amp alone is kept as it is, so a listener who raises it
    /// again is not overruled. The card shows the warning instead.
    public func guarded(from before: EqCurve) -> EqCurve {
        guard on, !before.on || before.gains != gains else { return self }
        return withRoom()
    }

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
