import Testing
@testable import RPMKit

/// What a stored glass colour means. The app's glass is white frost unless the user picks a colour.
struct GlassColourTests {
    @Test func nothingStoredIsNoColour() {
        #expect(GlassColour(stored: "") == .none)
        #expect(GlassColour(stored: "").value(on: .standard, supporter: true) == nil)
        #expect(GlassColour(stored: "").value(on: .pegasus, supporter: true) == nil)
    }

    /// No colour is stored as nothing, so picking it again gives the same app as a new install.
    @Test func noColourIsStoredAsNothing() {
        #expect(GlassColour.none.stored == "")
    }

    @Test func theBackgroundsColourFollowsTheBackground() {
        let background = GlassColour(stored: GlassColour.matchesBackground)
        #expect(background == .background)
        #expect(background.value(on: .standard, supporter: true) == 0x2563EB)
        #expect(background.value(on: .pegasus, supporter: true) == 0xD12A4E)
        #expect(background.value(on: .graphite, supporter: true) == 0x8E939B)
        #expect(background.stored == GlassColour.matchesBackground)
    }

    /// A colour is stored in the badge's own form, and reads back as the same colour on every
    /// background.
    @Test func aColourIsStoredAsTheBadgeStoresIt() {
        let red = GlassColour.colour(0xD12A4E)
        #expect(red.stored == RPMProfileBadges.wire(0xD12A4E))
        #expect(GlassColour(stored: red.stored) == red)
        #expect(red.value(on: .standard, supporter: true) == 0xD12A4E)
        #expect(red.value(on: .cocoa, supporter: true) == 0xD12A4E)
    }

    @Test func anythingElseIsNoColour() {
        #expect(GlassColour(stored: "none") == .none)
        #expect(GlassColour(stored: "teal") == .none)
        #expect(GlassColour(stored: "#12345") == .none)
        #expect(GlassColour(stored: "#GGGGGG") == .none)
    }

    /// A colour is a supporter feature: for anyone else every choice is no colour, on every
    /// background. The choice itself is kept, so it comes back for a supporter.
    @Test func anAccountThatIsNotASupportersShowsNoColour() {
        let red = GlassColour.colour(0xD12A4E)
        #expect(red.value(on: .standard, supporter: false) == nil)
        #expect(red.value(on: .cocoa, supporter: false) == nil)
        #expect(GlassColour.background.value(on: .pegasus, supporter: false) == nil)
        #expect(GlassColour(stored: red.stored) == red)
        #expect(red.value(on: .standard, supporter: true) == 0xD12A4E)
    }
}
