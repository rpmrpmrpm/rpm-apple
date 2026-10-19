import Foundation
import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/RadioResultsTests.cs`. Change both files
/// together. Radio Browser lists streams, not stations, so the answer is folded to one row per
/// station before the user can choose from it.

/// Builds a station as the directory lists it. Pass `stream` when the test is about the
/// address. Without it, the address is unique, so a test about names is not also a test about
/// addresses.
private func station(_ name: String, _ codec: String = "MP3", _ bitrate: Int = 128,
                     favicon: String? = nil, country: String = "NL",
                     reachable: Bool = true, uuid: String? = nil,
                     homepage: String? = nil, stream: String? = nil) -> RadioStation {
    var made = RadioStation(uuid: uuid ?? "\(name)-\(codec)-\(bitrate)",
                            name: name,
                            streamUrl: stream
                                ?? "http://example.test/\(name)/\(codec)/\(bitrate)/\(uuid ?? "")")
    made.codec = codec
    made.bitrateKbps = bitrate
    made.favicon = favicon
    made.homepage = homepage
    made.countryCode = country
    made.reachable = reachable
    return made
}

private func names(_ stations: [RadioStation]) -> [String] { stations.map(\.name) }

// ── the fold ──

/// The directory can return NPO Radio 1 twice: once as MP3 at 192k and once as AAC at 32k.
/// These are one station.
@Test func oneStationListedTwiceBecomesOneRow() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 1", "MP3", 192),
        station("NPO Radio 1", "AAC", 32),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 192)
}

/// The Spanish Kiss FM has many entries in the directory. The most-clicked entry is 56k, but
/// the best one to play is 128k. The fold keeps the 128k entry.
@Test func theMostClickedStreamDoesNotWinOnBitrate() {
    let picked = RadioResults.onePerStation([
        station("Kiss FM", "MP3", 56, country: "ES", uuid: "most-clicked"),
        station("Kiss FM", "MP3", 56, country: "ES", uuid: "second"),
        station("Kiss FM", "MP3", 128, country: "ES", uuid: "best"),
        station("Kiss FM", "MP3", 56, country: "ES", uuid: "last"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 128)
}

/// The logo is taken from whichever row has one, even when that row is the lower-quality one.
/// The kept row then gets the logo from its twin.
@Test func theBestStreamWearsTheLogoOffItsWorseTwin() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 1", "MP3", 192),
        station("NPO Radio 1", "AAC", 32, favicon: "http://npo.test/logo.png"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 192)
    #expect(picked[0].favicon == "http://npo.test/logo.png")
}

/// The directory checks whether each stream can be reached. A 320k stream that cannot be
/// reached is a worse choice than a 96k stream that can.
@Test func aStreamTheDirectoryCouldNotReachLosesToOneItCould() {
    let picked = RadioResults.onePerStation([
        station("Sky Radio", "MP3", 320, reachable: false),
        station("Sky Radio", "AAC", 96, reachable: true),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 96)
}

/// A stream with no stated bitrate ranks below every stream that has one. Treating a missing
/// bitrate as 0 would make the result depend on the order the directory returned the rows.
@Test func aStreamThatDeclaresNoBitrateLosesToOneThatDoes() {
    let picked = RadioResults.onePerStation([
        station("Qmusic", "MP3", 0),
        station("Qmusic", "MP3", 96),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 96)
}

/// Case, spaces and punctuation do not make two stations different.
@Test func theSameNameSpeltDifferentlyIsTheSameStation() {
    let picked = RadioResults.onePerStation([
        station("Q music Nederland", "AAC", 95),
        station("Q-Music  NEDERLAND", "MP3", 192),
    ])

    #expect(picked.count == 1)
}

/// A name is unique only within one country. Two stations with the same name in different
/// countries are kept as two rows.
@Test func theSameNameInTwoCountriesIsTwoStations() {
    let picked = RadioResults.onePerStation([
        station("Radio 1", "MP3", 128, country: "NL"),
        station("Radio 1", "MP3", 128, country: "GB"),
    ])

    #expect(picked.count == 2)
}

/// The directory sorts by play count. The fold keeps this order, so a merged station stays at
/// the position where it first appeared.
@Test func theDirectorysOwnOrderIsKept() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 1", "MP3", 192),
        station("Radio 538", "MP3", 128),
        station("NPO Radio 2", "MP3", 192),
        station("NPO Radio 1", "AAC", 32),
        station("Arrow Classic Rock", "MP3", 192),
        station("NPO Radio 2", "AAC", 64),
    ])

    #expect(names(picked) == ["NPO Radio 1", "Radio 538", "NPO Radio 2", "Arrow Classic Rock"])
}

/// A station without a logo is still shown. Many stations that people listen to have no logo.
@Test func aStationWithNoLogoStillAppears() {
    let picked = RadioResults.onePerStation([
        station("Radio 538", "MP3", 128),
        station("3FM", "MP3", 192),
    ])

    #expect(names(picked) == ["Radio 538", "3FM"])
    #expect(picked.allSatisfy { $0.favicon == nil })
}

@Test func aListWithNothingToCollapseComesBackAsItWas() {
    let one = [station("NPO Radio 1")]

    #expect(RadioResults.onePerStation(one) == one)
    #expect(RadioResults.onePerStation([]).isEmpty)
}

/// A station with no name cannot be matched by name, and it is not removed. Two such stations
/// with different addresses are two rows.
@Test func aNamelessStationStandsForItself() {
    let picked = RadioResults.onePerStation([
        station("", "MP3", 128, uuid: "a", stream: "http://one.test/a"),
        station("", "MP3", 128, uuid: "b", stream: "http://two.test/b"),
    ])

    #expect(picked.count == 2)
}

// ── the second key: one address contributed under several names ──

/// Anyone can add a stream, so one address can appear under several names. For example,
/// "NPO 2" and "NPO Radio 2" can use the same Icecast mount. They are one station, whatever
/// their names.
@Test func oneAddressUnderTwoNamesBecomesOneRow() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 2", "MP3", 192, stream: "http://icecast.omroep.nl/radio2-bb-mp3"),
        station("NPO 2", "MP3", 192, stream: "http://icecast.omroep.nl/radio2-bb-mp3"),
    ])

    #expect(picked.count == 1)
    // The first row in the directory's order is kept.
    #expect(picked.first?.name == "NPO Radio 2")
}

/// Neither key matches all four rows alone. The two MP3 rows share an address, the two AAC
/// rows share an address, and the names link the two pairs.
@Test func namesAndAddressesTogetherReachWhatNeitherReachesAlone() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 2", "MP3", 192, stream: "http://icecast.omroep.nl/radio2-bb-mp3"),
        station("NPO 2", "MP3", 192, stream: "http://icecast.omroep.nl/radio2-bb-mp3"),
        station("NPO Radio 2", "AAC", 64, stream: "https://icecast.omroep.nl/radio2-bb-aac"),
        station("NPO 2", "AAC", 64, stream: "http://icecast.omroep.nl/radio2-bb-aac"),
    ])

    #expect(picked.count == 1)
    #expect(picked.first?.bitrateKbps == 192)
    #expect(picked.first?.name == "NPO Radio 2")
}

/// The http and https forms of one address are the same stream. Directory entries often
/// differ on the scheme.
@Test func theSchemeIsNotPartOfTheAddress() {
    let picked = RadioResults.onePerStation([
        station("3FM", "MP3", 192, stream: "http://icecast.omroep.nl/3fm-bb-mp3"),
        station("NPO 3FM", "MP3", 192, stream: "https://icecast.omroep.nl/3fm-bb-mp3"),
        station("NPO 3FM Serious Radio", "MP3", 192, stream: "http://icecast.omroep.nl/3fm-bb-mp3/"),
    ])

    #expect(picked.count == 1)
}

/// A leading "www." and a trailing slash do not make a different address.
@Test func wwwAndATrailingSlashAreNotADifference() {
    let picked = RadioResults.onePerStation([
        station("Deep", stream: "http://www.stream.deep.radio/hd/"),
        station("Deep Radio", stream: "https://stream.deep.radio/hd"),
    ])

    #expect(picked.count == 1)
}

/// The port is part of the address. One host can serve a different station on each port.
@Test func aStatedPortTellsTwoStationsApart() {
    let picked = RadioResults.onePerStation([
        station("First", stream: "http://shared.test:8000/stream"),
        station("Second", stream: "http://shared.test:8010/stream"),
    ])

    #expect(picked.count == 2)
}

/// The query string is part of the address too. One CDN, such as
/// playerservices.streamtheworld.com, serves many stations. Dropping the query string would
/// merge stations that only share a host.
@Test func theQueryStringTellsTwoStationsApart() {
    let picked = RadioResults.onePerStation([
        station("One", stream: "https://cdn.test/api/livestream-redirect?station=ONE"),
        station("Two", stream: "https://cdn.test/api/livestream-redirect?station=TWO"),
    ])

    #expect(picked.count == 2)
}

/// The country is part of the key, as it is for the name. For example, CNN (US) and CNN UK
/// can share one address, and they are two stations.
@Test func oneAddressInTwoCountriesStaysTwoStations() {
    let picked = RadioResults.onePerStation([
        station("CNN", country: "US", stream: "https://tunein.cdnstream1.test/2868_96.mp3"),
        station("CNN UK", country: "GB", stream: "https://tunein.cdnstream1.test/2868_96.mp3"),
    ])

    #expect(picked.count == 2)
}

/// A row whose address cannot be parsed is matched by name only.
@Test func anUnreadableAddressLeavesTheNameToDoTheWork() {
    let picked = RadioResults.onePerStation([
        station("Pirate FM", "MP3", 192, stream: "not a url"),
        station("Pirate FM", "AAC", 32, stream: "also not a url"),
    ])

    #expect(picked.count == 1)
    #expect(picked.first?.bitrateKbps == 192)
}

/// Rows that match on neither key are kept, in their original order.
@Test func stationsThatShareNeitherKeyAllSurvive() {
    let picked = RadioResults.onePerStation([
        station("Alpha", stream: "http://a.test/one"),
        station("Beta", stream: "http://b.test/two"),
        station("Gamma", stream: "http://c.test/three"),
    ])

    #expect(names(picked) == ["Alpha", "Beta", "Gamma"])
}

// ── all logo URLs are kept, because the URL does not show which one loads ──

/// These are real directory entries for NPO Radio 1, with their homepages. Each has a different
/// logo URL. The URLs do not show which one loads, so all of them are kept. The ranking only
/// sets the order to try: the station's own PNG on its homepage comes first, because it is
/// known to load.
@Test func theLogoMostLikelyToWorkIsTriedFirst() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 1", "MP3", 192, favicon: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/da/NPO_Radio_1_logo_2014.svg/640px-NPO_Radio_1_logo_2014.svg.png",
                homepage: "https://www.nporadio1.nl/"),
        station("NPO Radio 1", "MP3", 192, favicon: "https://www.nporadio1.nl/svg/npo_radio1_logo.svg",
                uuid: "svg", homepage: "https://www.nporadio1.nl/"),
        station("NPO Radio 1", "AAC", 64, favicon: "https://www.nporadio1.nl/apple-touch-icon.png",
                homepage: "https://www.nporadio1.nl/"),
        station("NPO Radio 1", "AAC", 32, favicon: "http://radio1.nl/apple-touch-icon.png",
                homepage: "http://radio1.nl/"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 192)

    // The station's own PNG, which loads.
    #expect(picked[0].favicon == "https://www.nporadio1.nl/apple-touch-icon.png")

    // The other logos follow, best first, so the view can try the next one if one fails.
    // A Wikimedia PNG ranks above the http logo on another site, because Wikimedia logos load.
    #expect(picked[0].otherLogos == [
        "https://www.nporadio1.nl/svg/npo_radio1_logo.svg",
        "https://upload.wikimedia.org/wikipedia/commons/thumb/d/da/NPO_Radio_1_logo_2014.svg/640px-NPO_Radio_1_logo_2014.svg.png",
        "http://radio1.nl/apple-touch-icon.png",
    ])
}

/// The ranking never removes a logo. A station whose only logo is on a host that refuses
/// requests still gets that logo, so the station is not left without a picture.
@Test func aBadlyRankedLogoIsStillKept() {
    let picked = RadioResults.onePerStation([
        station("Some Station", "MP3", 192,
                favicon: "https://upload.wikimedia.org/wikipedia/commons/logo.png"),
        station("Some Station", "AAC", 64),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "https://upload.wikimedia.org/wikipedia/commons/logo.png")
}

/// Logos that rank the same keep the order the directory gave them.
@Test func equalCandidatesKeepTheDirectorysOrder() {
    let picked = RadioResults.onePerStation([
        station("Some Station", "MP3", 192, favicon: "https://a.test/logo.png"),
        station("Some Station", "AAC", 64, favicon: "https://b.test/logo.png"),
        station("Some Station", "AAC", 32, favicon: "https://c.test/logo.png"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "https://a.test/logo.png")
    #expect(picked[0].otherLogos == ["https://b.test/logo.png", "https://c.test/logo.png"])
}

@Test func theSameLogoOnTwoEntriesIsListedOnce() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 2", "MP3", 192, favicon: "http://www.nporadio2.nl/apple-touch-icon.png"),
        station("NPO Radio 2", "AAC", 64, favicon: "http://www.nporadio2.nl/apple-touch-icon.png"),
        station("NPO Radio 2", "AAC", 32, favicon: "http://WWW.NPORADIO2.NL/apple-touch-icon.png"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].otherLogos.isEmpty)
}

/// A station with one logo has no alternatives, so `otherLogos` is empty.
@Test func oneLogoLeavesNoAlternates() {
    let picked = RadioResults.onePerStation([
        station("Radio 10", "MP3", 128, favicon: "http://r10.test/logo.png"),
        station("Radio 10", "AAC", 64),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "http://r10.test/logo.png")
    #expect(picked[0].otherLogos.isEmpty)
}

/// A site icon (`favicon.ico`) is a small browser-tab image. It is tried last, after pictures
/// and SVG drawings.
@Test func aSiteIconIsKeptAndTriedLast() {
    let picked = RadioResults.onePerStation([
        station("Sky Radio", "AAC", 64, favicon: "https://sky.test/favicon.ico"),
        station("Sky Radio", "MP3", 192, favicon: "https://sky.test/logo.png"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "https://sky.test/logo.png")
    #expect(picked[0].otherLogos == ["https://sky.test/favicon.ico"])
}

/// A site icon must not stop a real picture from being used. If the `.ico` counted as the
/// logo, the PNG on the twin row would be dropped, and the row would show the placeholder icon
/// while the real picture is one field away.
@Test func aSiteIconDoesNotDisplaceARealPicture() {
    let picked = RadioResults.onePerStation([
        station("NPO Radio 1", "MP3", 192, favicon: "https://nporadio1.test/favicon.ico"),
        station("NPO Radio 1", "AAC", 32, favicon: "https://nporadio1.test/logo.png"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].bitrateKbps == 192)
    #expect(picked[0].favicon == "https://nporadio1.test/logo.png")
}

/// If no logo can be drawn, the entry keeps its original `favicon` value instead of being set
/// to nil. The view shows the placeholder either way.
@Test func anUndrawableLogoSurvivesWhenNoTwinHasABetterOne() {
    let picked = RadioResults.onePerStation([
        station("Sky Radio", "MP3", 192, favicon: "https://sky.test/favicon.ico"),
        station("Sky Radio", "AAC", 64),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "https://sky.test/favicon.ico")
}

@Test func aLogoTheBestStreamAlreadyHasIsKept() {
    let picked = RadioResults.onePerStation([
        station("Radio 10", "MP3", 128, favicon: "http://r10.test/good.png"),
        station("Radio 10", "AAC", 64, favicon: "http://r10.test/other.png"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "http://r10.test/good.png")
}

/// All logo URLs in one list, best guess first, so the view can try each in turn.
@Test func theLogosAStationOffersAreOneList() {
    var bare = station("Radio 538")
    #expect(bare.logos.isEmpty)

    bare.favicon = "https://a.test/logo.png"
    bare.otherLogos = ["https://b.test/logo.png"]
    #expect(bare.logos == ["https://a.test/logo.png", "https://b.test/logo.png"])
}

/// These are results of the fold, not data about the station. A saved preset stores one
/// stream. The extra logos come from the directory and are rebuilt each time it is queried,
/// so they are not saved.
@Test func theExtraLogosAreNotSavedWithAPreset() throws {
    var made = station("Radio 538", favicon: "https://a.test/logo.png")
    made.otherLogos = ["https://b.test/logo.png"]

    let round = try JSONDecoder().decode(
        RadioStation.self, from: JSONEncoder().encode(made))

    #expect(round.favicon == "https://a.test/logo.png")
    #expect(round.otherLogos.isEmpty)
}

// ── the ranker ──

@Test func theBroadcastersOwnCopyBeatsAThirdPartys() {
    #expect(RadioLogo.rank("https://www.station.test/logo.png", homepage: "https://station.test/")
          > RadioLogo.rank("https://cdn.elsewhere.test/logo.png", homepage: "https://station.test/"))
}

/// The directory can give one broadcaster's address with and without "www." in one answer.
@Test func aWwwPrefixIsNotADifferentSite() {
    #expect(RadioLogo.rank("https://station.test/logo.png", homepage: "https://www.station.test/")
         == RadioLogo.rank("https://www.station.test/logo.png", homepage: "https://station.test/"))
}

/// Wikimedia is not treated as a host that refuses the app. A PNG there ranks the same as a
/// PNG on any other host.
@Test func wikimediaIsNotDockedAsAHostThatRefusesUs() {
    #expect(RadioLogo.rank("https://upload.wikimedia.org/logo.png", homepage: nil)
         == RadioLogo.rank("https://anywhere.test/logo.png", homepage: nil))
}

/// SVG drawings are not used by this app, so a PNG of the same logo on the same site ranks
/// above the SVG.
@Test func aPictureIsTriedBeforeADrawing() {
    #expect(RadioLogo.rank("https://station.test/logo.png", homepage: "https://station.test/")
          > RadioLogo.rank("https://station.test/logo.svg", homepage: "https://station.test/"))
}

@Test func aUrlThatIsNotAUrlRanksBelowEverything() {
    #expect(RadioLogo.rank("not a url", homepage: nil) == Int.min)
}

/// The file type is read from the URL path, not from the whole URL. A query string does not
/// change the type, and "favicon.ico" in a query string does not make it a site icon.
@Test func thePathIsWhatIsRankedNotTheWholeUrl() {
    #expect(RadioLogo.rank("https://a.test/logo.png?icon=favicon.ico", homepage: nil)
          > RadioLogo.rank("https://a.test/favicon.ico?v=2", homepage: nil))
}

/// The order is PNG, then SVG, then a URL with no extension, then a site icon. A site icon is
/// tried last. It is a small image that looks soft when enlarged.
@Test func aSiteIconRanksUnderEverythingElseWorthTrying() {
    #expect(RadioLogo.rank("https://a.test/logo.png", homepage: nil)
          > RadioLogo.rank("https://a.test/logo.svg", homepage: nil))
    #expect(RadioLogo.rank("https://a.test/logo.svg", homepage: nil)
          > RadioLogo.rank("https://a.test/logo", homepage: nil))
    #expect(RadioLogo.rank("https://a.test/logo", homepage: nil)
          > RadioLogo.rank("https://a.test/favicon.ico", homepage: nil))
}

@Test(arguments: [
    ("https://a.test/logo.png", true),
    ("http://a.test/logo.jpg", true),
    ("https://a.test/favicon.ico", true),
    ("ftp://a.test/logo.png", false),
    ("/relative/logo.png", false),
    ("", false),
])
func whatCountsAsALogoWorthTrying(favicon: String, drawable: Bool) {
    #expect(RadioLogo.isDrawable(favicon) == drawable)
}

@Test func nothingIsNotALogo() {
    #expect(!RadioLogo.isDrawable(nil))
}

// ── which picture, when the entries disagree ──

/// Builds an iHeart image URL for one asset at the given size.
private func brand(_ asset: String, _ size: Int) -> String {
    "https://i.iheart.com/v3/re/assets.brands/\(asset)?ops=gravity(%22center%22),contain(\(size),\(size))"
}

/// When a station's entries name different pictures, the picture named by more entries is
/// tried first.
///
/// For example, 102.7 KIIS FM has three entries. Two name its wordmark at different sizes,
/// and one names an unrelated letter. The URLs do not show which picture is the station's
/// mark, but the number of entries that name each picture does.
@Test func thePictureMoreEntriesNameIsTheOneTriedFirst() {
    let picked = RadioResults.onePerStation([
        station("KIIS FM", "AAC", 128, favicon: brand("theletter", 167)),
        station("KIIS FM", "MP3", 64, favicon: brand("thewordmark", 32)),
        station("KIIS FM", "MP3", 96, favicon: brand("thewordmark", 360)),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon?.contains("thewordmark") == true)

    // The letter is kept too, so the view tries it if the wordmark does not load.
    #expect(picked[0].otherLogos.contains { $0.contains("theletter") })
}

/// Two sizes of one asset count as one picture, not two. Comparing by address would make a
/// station whose entries all agree look split, and one odd entry could then win a tie.
@Test func oneAssetFiledAtTwoSizesIsOneCandidateToTry() {
    let picked = RadioResults.onePerStation([
        station("KIIS FM", "MP3", 64, favicon: brand("thewordmark", 32)),
        station("KIIS FM", "MP3", 96, favicon: brand("thewordmark", 360)),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon?.contains("thewordmark") == true)
}

/// Agreement is not the only rule, and it is not the strongest. A picture on the broadcaster's
/// own site ranks above a picture that several other entries name.
@Test func theStationsOwnCopyStillBeatsAPictureTwoEntriesAgreedOn() {
    let picked = RadioResults.onePerStation([
        station("KIIS FM", "AAC", 128, favicon: "https://kiisfm.test/logo.png",
                homepage: "https://kiisfm.test/"),
        station("KIIS FM", "MP3", 64, favicon: brand("amirror", 32),
                homepage: "https://kiisfm.test/"),
        station("KIIS FM", "MP3", 96, favicon: brand("amirror", 360),
                homepage: "https://kiisfm.test/"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].favicon == "https://kiisfm.test/logo.png")
}

/// Each resizing host has its own rule for the size. `samePicture` removes the size, so two
/// sizes of one asset compare equal.
@Test func oneAssetAtTwoSizesIsOnePicture() {
    #expect(RadioLogo.samePicture(brand("thewordmark", 32))
         == RadioLogo.samePicture(brand("thewordmark", 360)))

    #expect(RadioLogo.samePicture(brand("thewordmark", 32))
         != RadioLogo.samePicture(brand("theletter", 32)))

    // Wix keeps the verb in the address. `fill` crops the image and `fit` does not, so these
    // two are different pictures.
    let fill = "https://static.wixstatic.com/media/a_b.png/v1/fill/w_455,h_413,al_c/a_b.png"
    let fit = "https://static.wixstatic.com/media/a_b.png/v1/fit/w_455,h_413,al_c/a_b.png"
    #expect(RadioLogo.samePicture(fill) != RadioLogo.samePicture(fit))
    #expect(RadioLogo.samePicture(fill)
         == RadioLogo.samePicture(fill.replacingOccurrences(of: "w_455,h_413", with: "w_90,h_80")))

    // TuneIn takes a letter for the size, not a pixel count.
    #expect(RadioLogo.samePicture("https://cdn-profiles.tunein.com/s1/images/logod.png")
         == RadioLogo.samePicture("https://cdn-profiles.tunein.com/s1/images/logog.png"))

    // Other hosts are compared by their full address.
    #expect(RadioLogo.samePicture("https://a.test/logo.png") == "https://a.test/logo.png")
    #expect(RadioLogo.samePicture(nil) == "")
}

// ── the size the address asks for ──

/// iHeart entries often ask for 32 pixels, which is too small for a 40-point slot. The size in
/// the address is not part of the picture itself.
@Test func aResizingHostIsAskedForTheSizeItWillBeDrawnAt() {
    #expect(RadioLogo.sized(brand("mark", 32), edge: 120)
         == brand("mark", 120))

    // Only raise the size, never lower it. One address can be requested by a 40-point row and
    // by a tile several hundred points wide.
    #expect(RadioLogo.sized(brand("mark", 360), edge: 120) == brand("mark", 360))
}

/// Both sides are scaled by the same factor. The box is a crop as well as a size. Making the
/// box square would cut off the ends of a wide wordmark.
@Test func aWordmarksShapeIsKeptWhenItIsRaised() {
    let wide = "https://i.iheart.com/v3/re/a?ops=contain(100,50)"
    #expect(RadioLogo.sized(wide, edge: 150) == "https://i.iheart.com/v3/re/a?ops=contain(300,150)")
}

/// The size is never raised above the ceiling. The ceiling is measured on the longer side,
/// because that side sets how large the image is.
@Test func aRaisedAddressStopsAtTheCeiling() {
    let wide = "https://i.iheart.com/v3/re/a?ops=contain(2000,100)"
    #expect(RadioLogo.sized(wide, edge: 400) == wide)
}

/// Wix crops the upload, and the verb before the box sets the crop mode.
@Test func wixIsRaisedWithoutMovingItsCrop() {
    let small = "https://static.wixstatic.com/media/a.png/v1/crop/x_24,y_30,w_555,h_544/fill/w_50,h_50,al_c/a.png"
    let raised = RadioLogo.sized(small, edge: 150)

    // The box after the verb now has the new size.
    #expect(raised?.contains("fill/w_150,h_150") == true)
    // The crop before the verb is in source pixels, so it does not change.
    #expect(raised?.contains("crop/x_24,y_30,w_555,h_544") == true)
}

/// TuneIn takes one of four size letters. The smallest letter that covers the requested size
/// is used. If the address already has a large enough letter, it is not changed.
@Test func tuneInClimbsItsOwnLadder() {
    let small = "https://cdn-profiles.tunein.com/s1/images/logot.png"
    #expect(RadioLogo.sized(small, edge: 120) == "https://cdn-profiles.tunein.com/s1/images/logoq.png")
    #expect(RadioLogo.sized(small, edge: 500) == "https://cdn-profiles.tunein.com/s1/images/logog.png")

    // A size above the largest letter gets the largest letter.
    #expect(RadioLogo.sized(small, edge: 5000) == "https://cdn-profiles.tunein.com/s1/images/logog.png")

    let big = "https://cdn-profiles.tunein.com/s1/images/logog.png"
    #expect(RadioLogo.sized(big, edge: 120) == big)
}

/// Other hosts serve only the size that was uploaded, so their addresses are returned unchanged.
@Test func anOrdinaryAddressIsNotRewritten() {
    #expect(RadioLogo.sized("https://a.test/logo.png", edge: 120) == "https://a.test/logo.png")
    #expect(RadioLogo.sized(nil, edge: 120) == nil)
    #expect(RadioLogo.sized("https://a.test/logo.png", edge: 0) == "https://a.test/logo.png")
}


// ── one channel with several names and addresses ──

/// The Dutch station Qmusic has five entries, four spellings and three addresses. It is one
/// station. The name key merges the spellings, and the address key merges the rest.
@Test func theSpellingsOfOneChannelBecomeOneRow() {
    let picked = RadioResults.onePerStation([
        station("Qmusic", "MP3", 96, stream: "https://icecast-qmusicnl.test/Qmusic_nl_live_96.mp3"),
        station("Q-Music", "AAC+", 96, stream: "https://icecast-qmusicnl.test/Qmusic_nl_live_high"),
        station("Q music Nederland", "AAC+", 96, stream: "https://stream.qmusic.nl/qmusic/aachigh"),
        station("QMUSIC NEDERLAND", "MP3", 128, stream: "https://stream.qmusic.nl/qmusic/mp3"),
        station("QMUSIC NEDERLAND AAC HIGH", "AAC+", 95, stream: "https://stream.qmusic.nl/qmusic/aachigh"),
    ])

    #expect(picked.count == 1)
    #expect(picked.first?.bitrateKbps == 128)
}

/// Other channels of one broadcaster are separate stations, so they must not merge with the
/// main channel. Matching by prefix would merge all of them.
@Test func aBroadcastersOtherChannelsAreNotTheBroadcaster() {
    let picked = RadioResults.onePerStation([
        station("Qmusic", stream: "https://stream.qmusic.test/qmusic/mp3"),
        station("Qmusic Non-Stop", stream: "https://stream.qmusic.test/nonstop/mp3"),
        station("Qmusic Het Foute Uur", stream: "https://stream.qmusic.test/fouteuur/mp3"),
        station("Radio 10", stream: "https://stream.radio10.test/live"),
        station("Radio 10 non-stop", stream: "https://stream.radio10.test/nonstop"),
    ])

    #expect(picked.count == 5)
}

/// A country word at the start of a name is part of the brand, not a qualifier.
@Test func gbNewsIsNotANewsStationCalledUk() {
    let picked = RadioResults.onePerStation([
        station("GB News", country: "GB", stream: "https://listen.test/gbnews.mp3"),
        station("News Radio UK", country: "GB", stream: "https://listen.test/newsradio.mp3"),
    ])

    #expect(picked.count == 2)
}

/// Two Russian station names that differ only in non-ASCII letters are two stations.
@Test func twoStationsNamedInAnotherScriptStayTwo() {
    let picked = RadioResults.onePerStation([
        station("Вести FM", country: "RU", stream: "https://a.test/vesti"),
        station("Ретро FM", country: "RU", stream: "https://a.test/retro"),
    ])

    #expect(picked.count == 2)
}

/// The rows that were merged into the kept row are the same station. Their uuids are stored on
/// the kept row, so a lookup by any of those uuids (for example, the admin's hidden list)
/// finds it.
@Test func theRowKeptCarriesTheUuidsOfTheRowsFoldedIntoIt() {
    let picked = RadioResults.onePerStation([
        station("Kiss FM", "MP3", 56, country: "ES", uuid: "most-clicked"),
        station("Kiss FM", "MP3", 128, country: "ES", uuid: "best"),
        station("Kiss FM", "MP3", 56, country: "ES", uuid: "last"),
    ])

    #expect(picked.count == 1)
    #expect(picked[0].uuid == "best")
    #expect(Set(picked[0].alsoFiledAs) == ["most-clicked", "last"])
    #expect(picked[0].isFiled(as: "LAST"))
    #expect(picked[0].isFiled(as: "best"))
    #expect(picked[0].isFiled(as: "somebody-else") == false)
}

@Test func aStationListedOnceIsFiledUnderNothingElse() {
    let picked = RadioResults.onePerStation([station("NPO Radio 1", "MP3", 192)])

    #expect(picked[0].alsoFiledAs.isEmpty)
}
