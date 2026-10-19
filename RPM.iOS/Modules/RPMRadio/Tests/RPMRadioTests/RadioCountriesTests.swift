import Foundation
import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/RadioCountriesTests.cs`. Change both files
/// together. The input names are country names as Radio Browser publishes them.

/// A formal country name is shown as a shorter common name.
@Test(arguments: [
    ("The United Kingdom Of Great Britain And Northern Ireland", "GB", "United Kingdom"),
    ("The United States Of America", "US", "United States"),
    ("The Russian Federation", "RU", "Russia"),
    ("The Republic Of Korea", "KR", "South Korea"),
    ("The Democratic Peoples Republic Of Korea", "KP", "North Korea"),
    ("Taiwan, Republic Of China", "TW", "Taiwan"),
    ("Bolivarian Republic Of Venezuela", "VE", "Venezuela"),
    ("Islamic Republic Of Iran", "IR", "Iran"),
    ("Syrian Arab Republic", "SY", "Syria"),
    ("United Republic Of Tanzania", "TZ", "Tanzania"),
    ("The Republic Of Moldova", "MD", "Moldova"),
    ("Republic Of North Macedonia", "MK", "North Macedonia"),
    ("The Lao Peoples Democratic Republic", "LA", "Laos"),
    ("The Democratic Republic Of The Congo", "CD", "DR Congo"),
    ("State Of Palestine", "PS", "Palestine"),
    ("The Holy See", "VA", "Vatican City"),
])
func aCountryCalledSomethingElseEntirely(each: (String, String, String)) {
    #expect(RadioCountries.short(each.0, each.1) == each.2)
}

/// A leading "The" is removed.
@Test(arguments: [
    ("The Netherlands", "NL", "Netherlands"),
    ("The Philippines", "PH", "Philippines"),
    ("The United Arab Emirates", "AE", "United Arab Emirates"),
    ("The Dominican Republic", "DO", "Dominican Republic"),
    ("The Bahamas", "BS", "Bahamas"),
    ("The Gambia", "GM", "Gambia"),
    ("The Central African Republic", "CF", "Central African Republic"),
    ("The Faroe Islands", "FO", "Faroe Islands"),
])
func theArticleComesOff(each: (String, String, String)) {
    #expect(RadioCountries.short(each.0, each.1) == each.2)
}

/// The directory capitalises every word, so joining words such as "And" are lower-cased again.
@Test(arguments: [
    ("Trinidad And Tobago", "TT", "Trinidad and Tobago"),
    ("Bosnia And Herzegovina", "BA", "Bosnia and Herzegovina"),
    ("Isle Of Man", "IM", "Isle of Man"),
    ("Sao Tome And Principe", "ST", "Sao Tome and Principe"),
    ("Saint Vincent And The Grenadines", "VC", "Saint Vincent and the Grenadines"),
])
func theJoiningWordsComeBackDown(each: (String, String, String)) {
    #expect(RadioCountries.short(each.0, each.1) == each.2)
}

/// A name that is already correct is returned unchanged.
@Test(arguments: [
    ("Germany", "DE"),
    ("France", "FR"),
    ("Türkiye", "TR"),
    ("Czechia", "CZ"),
    ("New Zealand", "NZ"),
    ("South Africa", "ZA"),
    ("Saudi Arabia", "SA"),
    ("Papua New Guinea", "PG"),
])
func aNameThatNeedsNothingIsLeftAlone(each: (String, String)) {
    #expect(RadioCountries.short(each.0, each.1) == each.0)
}

/// A country with no code is still tidied.
@Test func aCountryWithNoCodeIsStillTidied() {
    #expect(RadioCountries.short("The Netherlands", nil) == "Netherlands")
    #expect(RadioCountries.short("Isle Of Man", "") == "Isle of Man")
}

@Test(arguments: [nil, "", "   "] as [String?])
func nothingNamedIsNothingShown(name: String?) {
    #expect(RadioCountries.short(name, "XX") == "")
}

// ── forPicker ──

private func numbered(_ count: Int) -> [RadioFacet] {
    (0..<count).map {
        let n = String(format: "%03d", $0)
        return RadioFacet(name: "Country \(n)", code: "C\(n)", stationCount: 1000 - $0)
    }
}

private func code(_ n: Int) -> String { "C" + String(format: "%03d", n) }

/// The picker offers the countries with the most stations, up to `offered` entries.
@Test func thePickerOffersTheCountriesWithTheMostStations() {
    let offered = RadioCountries.forPicker(numbered(RadioCountries.offered + 5))

    #expect(offered.count == RadioCountries.offered)
    #expect(!offered.contains { $0.code == code(RadioCountries.offered) })
    #expect(offered.contains { $0.code == code(RadioCountries.offered - 1) })
}

/// Sorted A to Z by the shown name. "Netherlands" sorts under N and "United Kingdom" under U.
@Test func thePickerSortsByTheShortName() {
    let offered = RadioCountries.forPicker([
        RadioFacet(name: "The United Kingdom Of Great Britain And Northern Ireland", code: "GB",
                   stationCount: 3000),
        RadioFacet(name: "Germany", code: "DE", stationCount: 2000),
        RadioFacet(name: "The Netherlands", code: "NL", stationCount: 1000),
        RadioFacet(name: "Austria", code: "AT", stationCount: 500),
    ])

    #expect(offered.map(\.name) == ["Austria", "Germany", "Netherlands", "United Kingdom"])
}

/// Sorted as names, not by Unicode code point, so "Türkiye" sorts between "Tunisia" and "Uganda".
@Test func thePickerSortsAccentedNamesWithTheirLetter() {
    let offered = RadioCountries.forPicker([
        RadioFacet(name: "Uganda", code: "UG", stationCount: 30),
        RadioFacet(name: "Türkiye", code: "TR", stationCount: 20),
        RadioFacet(name: "Tunisia", code: "TN", stationCount: 10),
    ])

    #expect(offered.map(\.name) == ["Tunisia", "Türkiye", "Uganda"])
}

/// The directory can list Brazil twice, as "BR" and as "br". The picker shows one entry with
/// the two station counts added together.
@Test func thePickerShowsOneEntryPerCode() {
    let offered = RadioCountries.forPicker([
        RadioFacet(name: "Brazil", code: "BR", stationCount: 1759),
        RadioFacet(name: "Brazil", code: "br", stationCount: 1),
        RadioFacet(name: "Italy", code: "IT", stationCount: 1861),
    ])

    #expect(offered.map(\.name) == ["Brazil", "Italy"])
    #expect(offered[0].stationCount == 1760)
    #expect(offered[0].code == "BR")
}

/// When two countries tie at the cut-off, the country code decides, not the order of the list.
@Test func aTieAtTheCutIsDecidedByCode() {
    let full = numbered(RadioCountries.offered - 1)
    let zeta = RadioFacet(name: "Zeta", code: "ZZ", stationCount: 5)
    let alpha = RadioFacet(name: "Alpha", code: "AA", stationCount: 5)

    let one = RadioCountries.forPicker(full + [zeta, alpha])
    let other = RadioCountries.forPicker(full + [alpha, zeta])

    #expect(one.contains { $0.code == "AA" })
    #expect(!one.contains { $0.code == "ZZ" })
    #expect(one.map(\.code) == other.map(\.code))
}
