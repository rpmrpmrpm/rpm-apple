import Testing
@testable import RPMKit

/// iOS and tvOS decode only the file types Core Audio's stream parser reads. The starter songs that
/// every new collection gets are Ogg Vorbis, which it does not read.

private func track(_ path: String?, extension ext: String? = nil, codec: String? = nil) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.extension = ext
    tags.codecDescription = codec
    return CloudTrack(rpmId: "t", relativePath: path, tags: tags)
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
