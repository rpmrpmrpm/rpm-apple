import Testing
@testable import RPMDesign

/// The welcome's steps: the support step only while the account is asked, the song step only with a
/// song, and the page shown when the one asked for has dropped out.
@Suite("The welcome's steps")
struct WelcomeStepsTests {
    @Test("an account that is asked, with a song, has five steps, the support step fourth")
    func all() {
        let steps = WelcomeSteps(asks: true, hasSong: true)

        #expect(steps.steps == [.language, .look, .layout, .support, .spin])
        #expect(steps.number(of: .support) == 4)
        #expect(steps.number(of: .spin) == 5)
    }

    @Test("a supporter is not asked: no support step, and the layout step leads to the song")
    func supporter() {
        let steps = WelcomeSteps(asks: false, hasSong: true)

        #expect(steps.steps == [.language, .look, .layout, .spin])
        #expect(steps.after(.layout) == .spin)
    }

    @Test("with no song, the support step is the last")
    func noSong() {
        let steps = WelcomeSteps(asks: true, hasSong: false)

        #expect(steps.after(.layout) == .support)
        #expect(steps.after(.support) == nil)
    }

    @Test("after a purchase on the support step, the song shows")
    func boughtWithSong() {
        let steps = WelcomeSteps(asks: false, hasSong: true)

        #expect(steps.shown(for: .support) == .spin)
    }

    @Test("after a purchase on the support step with no song, nothing is left to show")
    func boughtWithoutSong() {
        let steps = WelcomeSteps(asks: false, hasSong: false)

        #expect(steps.shown(for: .support) == nil)
    }

    @Test("a page among the steps shows as itself, and the greeting always does")
    func shownAsItself() {
        let steps = WelcomeSteps(asks: false, hasSong: false)

        #expect(steps.shown(for: .hello) == .hello)
        #expect(steps.shown(for: .look) == .look)
    }

    @Test("a page is found by its name")
    func named() {
        #expect(WelcomePage.named("support") == .support)
        #expect(WelcomePage.named("spin") == .spin)
        #expect(WelcomePage.named("nothing") == nil)
    }
}
