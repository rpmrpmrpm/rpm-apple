import Testing
@testable import RPMRadio

/// Announcements a station garbled by turning them into UTF-8 twice are read back as they were meant.
struct StationSaidRepairTests {
    @Test func doubleEncodedTextIsRepaired() {
        #expect(StationSaid.repaired("TIÃ‹STO & AVA MAX - THE MOTTO") == "TIËSTO & AVA MAX - THE MOTTO")
        #expect(StationSaid.repaired("BeyoncÃ© - Halo") == "Beyoncé - Halo")
        #expect(StationSaid.of("TIÃ‹STO & AVA MAX - THE MOTTO", station: "Radio 538")
                == .song(artist: "TIËSTO & AVA MAX", title: "THE MOTTO"))
    }

    @Test func correctTextIsLeftAlone() {
        #expect(StationSaid.repaired("Beyoncé - Halo") == "Beyoncé - Halo")
        #expect(StationSaid.repaired("Ã la carte") == "Ã la carte")
        #expect(StationSaid.repaired("Sigur Rós - Hoppípolla") == "Sigur Rós - Hoppípolla")
        #expect(StationSaid.repaired("") == "")
    }
}
