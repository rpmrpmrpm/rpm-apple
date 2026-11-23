import Testing
@testable import RPMKit

/// iOS and tvOS decode only the file types Core Audio's stream parser reads. The starter songs that
/// every new collection gets are Ogg Vorbis, which it does not read.

private func track(_ path: String?, extension ext: String? = nil, codec: String? = nil,
                   id: String = "t") -> CloudTrack {
    var tags = CloudTrackTags()
    tags.extension = ext
    tags.codecDescription = codec
    return CloudTrack(rpmId: id, relativePath: path, tags: tags)
}

@Test(arguments: ["a.flac", "a.mp3", "a.m4a", "a.wav", "a.aiff", "A.FLAC"])
func aFileCoreAudioReadsDecodesHere(path: String) {
    #expect(PlaysHere.decodes(track(path)))
}

@Test(arguments: ["starter-gymnopedie.ogg", "a.oga", "a.opus", "a.wma", "a.ape", "a.wv", "noextension"])
func aFileCoreAudioDoesNotReadDoesNotDecodeHere(path: String) {
    #expect(!PlaysHere.decodes(track(path)))
}

@Test func aTrackWithNoPathAndNoExtensionDoesNotDecodeHere() {
    #expect(!PlaysHere.decodes(track(nil)))
}

/// The catalogue's extension is read before the path's, as the album page's format line reads it.
@Test func theCataloguedExtensionComesFirst() {
    #expect(!PlaysHere.decodes(track("a.flac", extension: ".ogg")))
    #expect(PlaysHere.decodes(track("a.ogg", extension: ".flac")))
}

@Test func dolbyInAnMpeg4FileDoesNotDecodeHere() {
    #expect(!PlaysHere.decodes(track("a.m4a", codec: "MPEG-4 Audio (ec-3)")))
    #expect(!PlaysHere.decodes(track("a.m4a", codec: "ac-3 surround")))
    #expect(PlaysHere.decodes(track("a.m4a", codec: "MPEG-4 Audio (alac)")))
}

/// Tag readers name AC-3 and E-AC-3 in several ways. Each of them is caught.
@Test(arguments: ["E-AC-3", "Dolby Digital Plus", "Dolby Digital", "Enhanced AC-3",
                  "Enhanced AC3 (E-AC-3)", "ATSC A/52", "MPEG-4 Audio (ac-3)", "AC3", "AC 3"])
func everyNameForDolbyDoesNotDecodeHere(codec: String) {
    #expect(!PlaysHere.decodes(track("a.m4a", codec: codec)))
}

/// Codec texts of formats that do decode here are not caught by the wider check.
@Test(arguments: ["MPEG-4 Audio (mp4a)", "MPEG-4 Audio (alac)", "MPEG-4 Audio (aac)",
                  "Apple Lossless", "FLAC", "MPEG-1 Layer 3", "PCM"])
func aCodecThatDecodesHereIsNotCaught(codec: String) {
    #expect(PlaysHere.decodes(track("a.m4a", codec: codec)))
}

/// The original of a file that does not decode here is asked for as the top AAC copy. Every other
/// setting, and every original that decodes here, is asked for as it is.
@Test func anOggOriginalIsAskedForAtTheTopLossyRate() {
    let ogg = track("Satie/starter-gymnopedie.ogg")
    #expect(AudioLadder.asked(AudioLadder.original, for: ogg).kilobits == 320)
    #expect(AudioLadder.asked(256, for: ogg).kilobits == 256)
    #expect(AudioLadder.asked(128, for: ogg).kilobits == 128)
}

@Test func aFlacOriginalIsAskedForAsTheOriginal() {
    let flac = track("Satie/Gnossienne.flac")
    #expect(AudioLadder.asked(AudioLadder.original, for: flac).kilobits == AudioLadder.original)
    #expect(AudioLadder.asked(320, for: flac).kilobits == 320)
}

/// **The catalogue can be silent.** An E-AC-3 file in an `.m4a` with no codec text looks like
/// AAC, so its original is asked for. Once this device has found that it cannot decode it, the
/// AAC copy is asked for, at every later request.
@Test func anOriginalFoundNotToDecodeIsAskedForAsTheCopy() {
    let found = FoundUndecodable()
    let silent = track("Album/01 Song.m4a", id: "dolby-without-a-label")

    #expect(AudioLadder.asked(AudioLadder.original, for: silent, found: found).isTheOriginal)

    #expect(found.note(silent.rpmId))
    #expect(!found.note(silent.rpmId), "noted twice")
    #expect(found.contains(silent.rpmId))

    #expect(AudioLadder.asked(AudioLadder.original, for: silent, found: found).kilobits == 320)

    // A lossy setting is a copy already and is asked for as it is.
    #expect(AudioLadder.asked(192, for: silent, found: found).kilobits == 192)

    // Another track is not affected.
    let other = track("Album/02 Song.m4a", id: "another-track")
    #expect(AudioLadder.asked(AudioLadder.original, for: other, found: found).isTheOriginal)
}

@Test func anEmptyIdIsNeverNoted() {
    let found = FoundUndecodable()
    #expect(!found.note(""))
    #expect(!found.contains(""))
}
