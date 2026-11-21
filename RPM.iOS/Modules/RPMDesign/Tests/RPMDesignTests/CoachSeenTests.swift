import Testing
@testable import RPMDesign

/// The first-run hints answered, how they are kept, and which one shows next.
@Suite("The hints seen")
struct CoachSeenTests {
    @Test("nothing is seen at first")
    func empty() {
        let seen = CoachSeen()

        #expect(!seen.has("home"))
        #expect(seen.stored == "")
    }

    @Test("a hint answered stays answered")
    func see() {
        var seen = CoachSeen()
        seen.see("home")

        #expect(seen.has("home"))
        #expect(!seen.has("radio"))
    }

    @Test("the mark for everything answers every hint")
    func everything() {
        let seen = CoachSeen.everything

        #expect(seen.has("home"))
        #expect(seen.has("player-grip"))
        #expect(seen.has("tour-done"))
    }

    @Test("seeing a hint under the mark for everything changes nothing")
    func seeUnderEverything() {
        var seen = CoachSeen.everything
        seen.see("home")

        #expect(seen == .everything)
    }

    @Test("kept as one key per line and read back the same")
    func roundTrip() {
        var seen = CoachSeen()
        seen.see("radio")
        seen.see("home")

        #expect(seen.stored == "home\nradio")
        #expect(CoachSeen(stored: seen.stored) == seen)
    }

    @Test("blank lines and a missing value read as nothing seen")
    func readsLoosely() {
        #expect(CoachSeen(stored: nil) == CoachSeen())
        #expect(CoachSeen(stored: "") == CoachSeen())
        #expect(CoachSeen(stored: "\nhome\n\n") == CoachSeen(keys: ["home"]))
    }

    @Test("the first hint not answered shows")
    func dueInOrder() {
        var seen = CoachSeen()
        seen.see("home")

        let due = seen.due(in: ["home", "collection", "radio"]) { _ in true }

        #expect(due == "collection")
    }

    /// The mini player's hint waits while nothing is loaded, and the tour goes on without it.
    @Test("a hint whose part is not on the screen waits, and the next one shows")
    func waitsForItsPart() {
        let seen = CoachSeen()

        let due = seen.due(in: ["mini-player", "settings"]) { $0 != "mini-player" }

        #expect(due == "settings")
    }

    @Test("nothing shows once every hint of the tour is answered")
    func tourOver() {
        var seen = CoachSeen()
        seen.see("home")
        seen.see("radio")

        #expect(seen.due(in: ["home", "radio"]) { _ in true } == nil)
    }
}

/// Whether a phone is new to rpm, decided on the first run of a build with the welcome.
@Suite("The first run")
struct FirstRunRuleTests {
    @Test("somebody already signed in has had the app: no welcome, no hints")
    func signedIn() throws {
        let settled = try #require(FirstRunRule.settle(decided: false, signedIn: true))

        #expect(settled.welcomed)
        #expect(settled.seen == .everything)
    }

    @Test("somebody who still has to sign in is new and sees both")
    func signedOut() throws {
        let settled = try #require(FirstRunRule.settle(decided: false, signedIn: false))

        #expect(!settled.welcomed)
        #expect(settled.seen == CoachSeen())
    }

    @Test("decided once, and never again")
    func once() {
        #expect(FirstRunRule.settle(decided: true, signedIn: true) == nil)
        #expect(FirstRunRule.settle(decided: true, signedIn: false) == nil)
    }
}
