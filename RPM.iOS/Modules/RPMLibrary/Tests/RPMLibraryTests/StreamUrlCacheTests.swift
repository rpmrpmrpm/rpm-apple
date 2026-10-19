import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The desktop (C#) has no tests for this. A failure here is heard by the listener: a URL that is used
/// after its signature expires gives a 403 error in the middle of a song.

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var at = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { at } }
    func advance(_ seconds: TimeInterval) { lock.withLock { at += seconds } }
}

private func signed(_ url: String, _ kbps: Int,
                    _ kind: StreamKind = .stored) -> StreamUrlCache.Signed {
    StreamUrlCache.Signed(url: URL(string: url)!, kilobits: kbps, kind: kind)
}

/// **A live address stops being the right answer as soon as the encode it names finishes.** The
/// address then says `kilobits == rate`, because a live encode serves exactly what was asked for.
/// If it were kept for hours (the life of a stored object), each play of that track would go back to
/// the transcoder and encode again a file that is already in the store. That costs a cold start and
/// extra encode time for a file that was not needed.
///
/// A fallback address is kept for minutes, because it is held while the requested rendition is being
/// made. A live address is also kept for minutes, because what it encodes soon becomes a stored object.
@Test func aLiveAddressIsNotTrustedForHours() {
    let clock = Clock()
    let cache = StreamUrlCache(now: { clock.now })

    cache.note("a", asked: 320, signed: signed("https://live/a", 320, .live))

    clock.advance(StreamUrlCache.fallbackLife + 1)

    #expect(cache.known("a", rate: 320) == nil,
            "a live address outlived the encode it names")
}

/// A stored object keeps the long life. Its signed URL points to a file that exists, so asking for it
/// again would only add a round trip.
@Test func anObjectIsStillTrustedForHours() {
    let clock = Clock()
    let cache = StreamUrlCache(now: { clock.now })

    cache.note("a", asked: 320, signed: signed("https://s3/a", 320, .stored))

    clock.advance(StreamUrlCache.fallbackLife + 1)

    #expect(cache.known("a", rate: 320) != nil)
}

/// A cached address is seeked the way it was served, so the kind must be kept. An encode stored as an
/// object would get range requests sent to the transcoder, which answers with the start of the record
/// rather than the requested position.
@Test func theCacheRemembersWhichKindOfAddressItIs() {
    let cache = StreamUrlCache()
    cache.note("a", asked: 320, signed: signed("https://live/a", 320, .live))

    #expect(cache.known("a", rate: 320)?.kind == .live)
}

@Test func aFreshUrlComesBack() {
    let cache = StreamUrlCache()
    cache.note("a", asked: 320, signed: signed("https://s3/a", 320))
    #expect(cache.known("a", rate: 320)?.kilobits == 320)
}

@Test func nothingIsKnownAboutATrackNobodyHasAskedFor() {
    #expect(StreamUrlCache().known("a", rate: 320) == nil)
}

/// The same track at two rates is stored as two separate entries. A cache that answered across rates
/// would keep serving the old quality after the rate changes.
@Test func theRateIsPartOfTheKey() {
    let cache = StreamUrlCache()
    cache.note("a", asked: 320, signed: signed("https://s3/a-320", 320))

    #expect(cache.known("a", rate: 320) != nil)
    #expect(cache.known("a", rate: 128) == nil)
}

@Test func aUrlServedAtTheRateAskedForLastsFourHours() {
    let clock = Clock()
    let cache = StreamUrlCache(now: { clock.now })
    cache.note("a", asked: 320, signed: signed("https://s3/a", 320))

    clock.advance(StreamUrlCache.urlLife - 1)
    #expect(cache.known("a", rate: 320) != nil)

    clock.advance(2)
    #expect(cache.known("a", rate: 320) == nil, "a URL outlived its signature")
}

/// The request that produced a fallback also started the transcoder, so the asked-for rendition is
/// usually only minutes away. Kept for four hours, the fallback would keep being served long after the
/// 320 kbps rendition exists.
@Test func aFallbackIsTrustedForMinutesRatherThanHours() {
    let clock = Clock()
    let cache = StreamUrlCache(now: { clock.now })

    // Asked for 320, served 128: a rendition that has not been made yet.
    cache.note("a", asked: 320, signed: signed("https://s3/a-128", 128))

    clock.advance(StreamUrlCache.fallbackLife - 1)
    #expect(cache.known("a", rate: 320)?.kilobits == 128)

    clock.advance(2)
    #expect(cache.known("a", rate: 320) == nil, "a fallback was trusted for the afternoon")
}

/// The fallback is stored under the rate that was asked for, not the rate that was served. Storing it
/// under the served rate would leave the asked-for key empty, so every play would sign a new URL.
@Test func aFallbackIsFiledUnderTheRateThatWasAskedFor() {
    let cache = StreamUrlCache()
    cache.note("a", asked: 320, signed: signed("https://s3/a-128", 128))

    #expect(cache.known("a", rate: 320) != nil)
    #expect(cache.known("a", rate: 128) == nil)
}

@Test func aPhoneLeftPlayingAllDayDoesNotAccumulateForever() {
    let cache = StreamUrlCache()
    for i in 0..<(StreamUrlCache.urlsKept + 10) {
        cache.note("t\(i)", asked: 320, signed: signed("https://s3/t\(i)", 320))
    }
    #expect(cache.count <= StreamUrlCache.urlsKept)
}

/// Cleared on sign-out or when a share is revoked. A URL signed for a grant that no longer exists would
/// fail with a 403 error.
@Test func forgettingLeavesNothingSigned() {
    let cache = StreamUrlCache()
    cache.note("a", asked: 320, signed: signed("https://s3/a", 320))
    cache.forget()
    #expect(cache.known("a", rate: 320) == nil)
}

/// Expiry is checked against the clock, not a timer. A timer stops while the phone sleeps, but a URL's
/// signature keeps running.
@Test func aUrlThatExpiredWhileThePhoneSleptIsGone() {
    let clock = Clock()
    let cache = StreamUrlCache(now: { clock.now })
    cache.note("a", asked: 320, signed: signed("https://s3/a", 320))

    clock.advance(24 * 60 * 60)   // the phone was asleep overnight
    #expect(cache.known("a", rate: 320) == nil)
}
