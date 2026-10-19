import Foundation
import Testing
import RPMKit
@testable import RPMRadio

@Suite struct StationBlurbsTests {
    @Test func theOpenGraphLineComesBeforeThePlainOne() {
        let page = """
        <html><head><meta name="description" content="The plain line about this station.">
        <meta property="og:description" content="The social line about this station."></head>
        """
        #expect(StationBlurbs.fromPage(page) == "The social line about this station.")
    }

    @Test func thePlainLineIsUsedWhenThereIsNoOther() {
        let page = "<meta content='Jazz all day and all night.' name='description'>"
        #expect(StationBlurbs.fromPage(page) == "Jazz all day and all night.")
    }

    @Test func aLongLineIsCutAtASentenceEndOrAWord() {
        let sentences = "Radio from the hills since 1979. We play folk, blues and the news every hour of the day."
        #expect(StationBlurbs.shorten(sentences) == "Radio from the hills since 1979.")

        let words = String(repeating: "word ", count: 30)
        let cut = StationBlurbs.shorten(words)!
        #expect(cut.hasSuffix("\u{2026}"))
        #expect(cut.count <= StationBlurbs.longest)
    }

    @Test func entitiesAreReadAndTooShortIsNothing() {
        #expect(StationBlurbs.shorten("Rock &amp; roll &#8211; all day") == "Rock & roll \u{2013} all day")
        #expect(StationBlurbs.shorten("Hi") == nil)
        #expect(StationBlurbs.shorten("   ") == nil)
    }

    /// A card shows its line, or no line, once the line has been requested. Until then the state is
    /// unknown, which is different from having no line.
    @Test func whatIsAnsweredIsKnownAtOnce() {
        let blurbs = StationBlurbs(reach: NetworkReach())
        var noPage = RadioStation(uuid: "no-page", name: "No page", streamUrl: "http://example.test/a")
        noPage.homepage = nil
        var page = RadioStation(uuid: "page", name: "Page", streamUrl: "http://example.test/b")
        page.homepage = "https://example.test/"

        // A station with no homepage has no line. This is known without a request.
        #expect(blurbs.answered(noPage) == .some(nil))
        // A station with a homepage that has not been requested yet is unknown.
        #expect(blurbs.answered(page) == nil)
    }

    /// A page that fails to load is requested again. A page that loads is kept, and it is not
    /// requested again.
    @Test func aPageThatCouldNotBeReadIsAskedAgain() async {
        let asks = Asks()
        let blurbs = StationBlurbs(fetch: { request in
            let n = await asks.count()
            let status = n == 1 ? 503 : 200
            let page = "<meta name='description' content='Folk and blues from the hills.'>"
            return (Data(page.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                                     httpVersion: nil, headerFields: nil)!)
        })
        var station = RadioStation(uuid: "hills", name: "Hills", streamUrl: "http://example.test/s")
        station.homepage = "https://example.test/"

        #expect(await blurbs.of(station) == nil)
        #expect(blurbs.answered(station) == nil, "a 503 was kept as no line")

        #expect(await blurbs.of(station) == "Folk and blues from the hills.")
        #expect(blurbs.answered(station) == .some("Folk and blues from the hills."))

        _ = await blurbs.of(station)
        #expect(await asks.count() == 3, "a page that answered was asked again")
    }

    actor Asks {
        private var made = 0
        func count() -> Int { made += 1; return made }
    }
}
