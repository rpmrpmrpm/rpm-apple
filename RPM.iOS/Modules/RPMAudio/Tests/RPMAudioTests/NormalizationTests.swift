import Testing
import Foundation
import RPMKit
@testable import RPMAudio

private let quietTrack = Level(lufs: -24, truePeak: 0.5)
private let loudRecord = Level(lufs: -12, truePeak: 0.5)

@Test func levellingOffMeansNothingIsTouched() {
    let decision = Normalization.resolve(NormalizeContext(mode: .off),
                                         track: quietTrack, album: loudRecord)
    #expect(decision == .none)
    #expect(!decision.applies)
}

/// **Album gain in album order, track gain on shuffle.** A quiet song on a record is meant to be
/// quiet in its place. When it plays between songs from other records, it is simply a quiet track.
@Test func aRecordPlayedAsARecordIsLevelledAsOne() {
    let asARecord = Normalization.resolve(NormalizeContext(mode: .album, inAlbumOrder: true),
                                          track: quietTrack, album: loudRecord)
    #expect(asARecord.basis == .album)

    let shuffled = Normalization.resolve(NormalizeContext(mode: .album, inAlbumOrder: false),
                                         track: quietTrack, album: loudRecord)
    #expect(shuffled.basis == .track)
}

@Test func trackModeIsTrackModeWhateverTheOrder() {
    let decision = Normalization.resolve(NormalizeContext(mode: .track, inAlbumOrder: true),
                                         track: quietTrack, album: loudRecord)
    #expect(decision.basis == .track)
}

/// When the album has no measurement, the track's own reading is used. The track then plays at an
/// even level without waiting for the album.
@Test func albumModeFallsBackToTheTracksOwnReading() {
    let decision = Normalization.resolve(NormalizeContext(mode: .album),
                                         track: quietTrack, album: .unknown)
    #expect(decision.basis == .track)
}

@Test func aTrackNobodyMeasuredIsLeftAlone() {
    let decision = Normalization.resolve(NormalizeContext(mode: .album),
                                         track: .unknown, album: .unknown)
    #expect(decision == .none)
}

// ── the classical rule ──

/// A quiet movement in a symphony is meant to be quiet. A loudness meter would read it as a
/// record at the wrong level, so classical music is not levelled by default.
@Test func classicalIsLeftAloneUnlessAskedFor() {
    var context = NormalizeContext(mode: .album, albumIsClassical: true)
    #expect(!Normalization.isOn(context))

    context.includeClassical = true
    #expect(Normalization.isOn(context))
}

/// The classical flag belongs to the source. The engine has one setting for all sources, so the
/// flag for each record must travel with its audio.
@Test func aSourceFromAClassicalRecordIsNotLevelled() {
    let measured = Level(lufs: -12, truePeak: 0.25)
    let classical = SourceLoudness(track: measured, album: measured, inAlbumOrder: true,
                                   albumIsClassical: true)
    let ordinary = SourceLoudness(track: measured, album: measured, inAlbumOrder: true,
                                  albumIsClassical: false)
    let setting = NormalizeContext(mode: .album)

    #expect(classical.gain(under: setting) == .none)
    #expect(ordinary.gain(under: setting).applies)
}

@Test func aSourceFromAClassicalRecordIsLevelledWhenTheSettingSaysSo() {
    let measured = Level(lufs: -12, truePeak: 0.25)
    let classical = SourceLoudness(track: measured, album: measured, inAlbumOrder: true,
                                   albumIsClassical: true)

    #expect(classical.gain(under: NormalizeContext(mode: .album, includeClassical: true)).applies)
}

/// A setting that carries a classical flag must not apply that flag to a source that is not
/// classical.
@Test func theSourceSaysWhetherItIsClassicalNotTheSetting() {
    let measured = Level(lufs: -12, truePeak: 0.25)
    let ordinary = SourceLoudness(track: measured, album: measured, inAlbumOrder: true,
                                  albumIsClassical: false)

    #expect(ordinary.gain(under: NormalizeContext(mode: .album, albumIsClassical: true)).applies)
}

/// **The listener's own choice for a record overrides every rule**, including the classical
/// rule. A listener who turns levelling on for a boxed set has given a more specific answer than
/// the default for classical music.
@Test func whatTheListenerSaidAboutThisRecordSettlesIt() {
    #expect(Normalization.isOn(NormalizeContext(mode: .album, albumOverride: true,
                                                albumIsClassical: true)))
    #expect(!Normalization.isOn(NormalizeContext(mode: .album, albumOverride: false)))

    // Even with levelling off globally.
    #expect(Normalization.isOn(NormalizeContext(mode: .off, albumOverride: true)))
}

// ── reading the loudness of a catalogue row ──

/// Zero means "not measured" in both fields. A real loudness reading is negative, since music is
/// below full scale.
@Test func aRowWithNoMeasurementSaysSo() {
    #expect(!Level(CloudTrackTags()).known)
    #expect(!Level(nil).known)

    var tags = CloudTrackTags()
    tags.loudnessLufs = -14.2
    tags.truePeak = 0.98

    let level = Level(tags)
    #expect(level.known)
    #expect(level.truePeak == 0.98)
}

/// A gain under 0.01 dB is not audible, so it is not applied. The audio path stays bypassed.
@Test func aGainTooSmallToHearDoesNotApply() {
    let barely = NormalizeDecision(gainDb: 0.004, basis: .track)
    #expect(!barely.applies)

    #expect(NormalizeDecision(gainDb: 0.5, basis: .track).applies)
}
