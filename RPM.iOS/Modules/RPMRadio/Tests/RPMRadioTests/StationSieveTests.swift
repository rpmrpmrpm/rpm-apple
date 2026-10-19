import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/StationSieveTests.cs`, except the advertising
/// tests. Change both files together.
///
/// **Most tests check that a station is NOT kept.** A wrong filter fails by hiding a station.
/// A listener who has narrowed the dial cannot tell a hidden station from one the directory
/// never had.

private func station(_ name: String = "Test FM", codec: String? = "MP3",
                     tags: [String] = []) -> RadioStation {
    var made = RadioStation(uuid: name, name: name, streamUrl: "http://example.test/stream")
    made.codec = codec
    made.tags = tags
    return made
}

@Test func aSieveThatAsksNothingKeepsEverybody() {
    let all = [station("A"), station("B", codec: nil), station("C", codec: "FLAC")]

    #expect(!StationSieve.off.isOn)
    #expect(StationSieve.off.through(all).map(\.uuid) == ["A", "B", "C"])
}

@Test(arguments: [
    ("MP3", "MP3", true),
    ("mp3", "MP3", true),
    ("AAC+", "AAC+", true),
    ("AACP", "AAC+", true),
    ("VORBIS", "OGG", true),
    // AAC and AAC+ are two separate menu entries. Choosing one does not choose the other.
    ("AAC+", "AAC", false),
    ("AAC", "AAC+", false),
    ("MP3", "OGG", false),
])
func aFormatIsTheCodecTheStationFiled(each: (String, String, Bool)) {
    #expect(StationSieve(format: each.1).keeps(station(codec: each.0)) == each.2)
}

/// A station can list several codecs in one field. Each codec is checked on its own.
@Test(arguments: [("AAC+,H.264", "AAC+"), ("MP3, OGG", "OGG")])
func aStationThatFilesTwoCodecsAnswersForBoth(each: (String, String)) {
    #expect(StationSieve(format: each.1).keeps(station(codec: each.0)))
}

/// An empty codec does not match any format.
@Test(arguments: [nil, ""] as [String?])
func aStationThatFiledNoCodecIsNotKeptByAFormat(codec: String?) {
    #expect(!StationSieve(format: "MP3").keeps(station(codec: codec)))
}

/// Directory tags are entered by users, so one genre is often written in many ways.
@Test(arguments: ["hip hop", "hip-hop", "HipHop", "rap", "urban"])
func aGenreIsReadThroughRadiosOwnList(tag: String) {
    #expect(StationSieve(genre: "Hip-Hop").keeps(station(tags: [tag])))
}

/// The dial includes spoken-word stations, not only music.
@Test(arguments: [
    ("talk", "Talk"), ("talk show", "Talk"), ("spoken word", "Talk"),
    ("news", "News"), ("newstalk", "News"),
    ("sport", "Sports"), ("sports talk", "Sports"),
])
func theSpokenFormatsAreOnTheListToo(each: (String, String)) {
    #expect(StationSieve(genre: each.1).keeps(station(tags: [each.0])))
}

/// **Whole tags only.** "Classic rock" is its own genre and contains the word "rock". A rule
/// that searched inside tags would put every such station under Rock.
@Test func aTagThatMerelyHoldsAGenreIsNotThatGenre() {
    #expect(!StationSieve(genre: "Rock").keeps(station(tags: ["classic rock"])))
    #expect(StationSieve(genre: "Classic Rock").keeps(station(tags: ["classic rock"])))

    #expect(!StationSieve(genre: "Dance").keeps(station(tags: ["dancehall"])))
    #expect(StationSieve(genre: "Reggae").keeps(station(tags: ["dancehall"])))
}

@Test(arguments: [("pop music", "Pop"), ("Jazz Radio", "Jazz"), ("classical music", "Classical")])
func aGenreWithTheObviousNounOnTheEndIsStillThatGenre(each: (String, String)) {
    #expect(StationSieve(genre: each.1).keeps(station(tags: [each.0])))
}

/// Many stations put several genres in one tag. A rule that read only whole tags would leave
/// all of these stations with no genre.
@Test(arguments: [
    ("club dance electronic house trance", "Dance"),
    ("club dance electronic house trance", "Electronic"),
    ("rap hiphop rnb", "Hip-Hop"), ("rap hiphop rnb", "R&B / Soul"),
    ("local news", "News"), ("chillout+lounge", "Electronic"),
    ("drum & bass", "Electronic"), ("alternative / indie", "Rock"),
    ("noticias y deportes", "Sports"),
])
func aTagHoldingSeveralGenresIsAllOfThem(each: (String, String)) {
    #expect(StationSieve(genre: each.1).keeps(station(tags: [each.0])))
}

/// Words are matched as the longest run that is a known genre. A longer genre name wins over
/// its parts.
@Test func theLongestRunOfWordsThatIsAFormatWins() {
    #expect(StationSieve(genre: "Classic Rock").keeps(station(tags: ["classic rock cafe"])))
    #expect(!StationSieve(genre: "Rock").keeps(station(tags: ["classic rock cafe"])))

    #expect(StationSieve(genre: "Adult Contemporary").keeps(station(tags: ["80s soft rock"])))
    #expect(!StationSieve(genre: "Rock").keeps(station(tags: ["80s soft rock"])))
}

/// One tag can be written with or without accents. Many directory tags are not in English.
@Test(arguments: [
    ("música pop", "Pop"), ("musica pop", "Pop"),
    ("clásicos en español", "Latin"), ("regional mexicana", "Latin"),
    ("noticias locales", "News"), ("nachrichten", "News"),
    ("поп-музыка", "Pop"), ("разговорный", "Talk"),
])
func aTagIsReadWhateverItIsWrittenIn(each: (String, String)) {
    #expect(StationSieve(genre: each.1).keeps(station(tags: [each.0])))
}

@Test func aStationTaggedSomethingElseIsNotThatGenre() {
    #expect(!StationSieve(genre: "Jazz").keeps(station(tags: ["classical", "opera"])))
}

@Test func aStationWithNoTagsAtAllIsNotClaimedForAGenre() {
    #expect(!StationSieve(genre: "Jazz").keeps(station(tags: [])))
}

/// At most 20 genres, because the menu is read, not searched. The spoken formats are included.
@Test func theMenuIsTwentyKindsOfStationAtMost() {
    #expect(StationSieve.genres.count <= 20)
    #expect(StationSieve.genres.contains("Talk"))
    #expect(StationSieve.genres.contains("News"))
    #expect(StationSieve.genres.contains("Sports"))
}

/// Stream details, such as the bitrate or codec, and directory notes are not genres.
@Test func aSpecificationTagIsNotAGenre() {
    #expect(!StationSieve(genre: "Pop").keeps(station(tags: ["flac", "320k", "##browserfriendly"])))
}

/// A filter with both a format and a genre keeps a station only when both match.
@Test func twoQuestionsAreBothAnswered() {
    let jazzy = station(codec: "MP3", tags: ["jazz"])

    #expect(StationSieve(format: "MP3", genre: "Jazz").keeps(jazzy))
    #expect(!StationSieve(format: "OGG", genre: "Jazz").keeps(jazzy))
    #expect(!StationSieve(format: "MP3", genre: "Rock").keeps(jazzy))
}
