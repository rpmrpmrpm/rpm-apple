import Testing
import Foundation
@testable import RPMKit

private func client(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> RPMCloudClient {
    RPMCloudClient(transport: Transport(
        base: URL(string: "https://api.example.com")!,
        tokens: FixedTokens(token: "t"),
        reach: openLine(),
        session: stubbedSession(handler)))
}

private func client(_ status: Int, _ json: String) -> RPMCloudClient {
    RPMCloudClient(transport: Transport(
        base: URL(string: "https://api.example.com")!,
        tokens: FixedTokens(token: "t"),
        reach: openLine(),
        session: replying(status, json)))
}

// ── the catalogue ──

@Test func listFollowsTheCursorUntilItRunsOut() async throws {
    let calls = Box<Int>()
    let cloud = client { request in
        let n = (calls.value ?? 0) + 1
        calls.value = n
        return ok(request, n == 1
            ? #"{"files":[{"rpmId":"a","sha256":"x","addedAt":1}],"cursor":"c1","owner":null}"#
            : #"{"files":[{"rpmId":"b","sha256":"y","addedAt":2}],"cursor":null,"owner":null}"#)
    }

    let tracks = try await cloud.list(.own)
    #expect(tracks.map(\.rpmId) == ["a", "b"])
    #expect(calls.value == 2)
}

@Test func listReportsItsRunningCount() async throws {
    let calls = Box<Int>()
    let cloud = client { request in
        let n = (calls.value ?? 0) + 1
        calls.value = n
        return ok(request, n == 1
            ? #"{"files":[{"rpmId":"a","sha256":"x","addedAt":1}],"cursor":"c1","owner":null}"#
            : #"{"files":[{"rpmId":"b","sha256":"y","addedAt":2}],"cursor":null,"owner":null}"#)
    }

    let counted = Box<[Int]>()
    counted.value = []
    _ = try await cloud.list(.own) { n in counted.value = (counted.value ?? []) + [n] }
    #expect(counted.value == [1, 2])
}

/// The one that matters. A borrowed listing that comes back without saying whose
/// it is, is the caller's own library under a stranger's name, and every symptom
/// after that is a client working confidently on the wrong music.
@Test func aBorrowedListingThatDoesNotSayWhoseItIsThrows() async {
    let cloud = client(200,
        #"{"files":[{"rpmId":"mine","sha256":"x","addedAt":1}],"cursor":null,"owner":null}"#)

    await #expect(throws: RPMError.self) {
        _ = try await cloud.list(.of("someone-else"))
    }
}

@Test func aBorrowedListingThatNamesItsOwnerIsKept() async throws {
    let cloud = client(200,
        #"{"files":[{"rpmId":"theirs","sha256":"x","addedAt":1}],"cursor":null,"owner":"someone-else"}"#)
    let tracks = try await cloud.list(.of("someone-else"))
    #expect(tracks.map(\.rpmId) == ["theirs"])
}

@Test func listSendsTheOwnerAfterTheLimit() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"files":[],"cursor":null,"owner":"owner-1"}"#)
    }
    _ = try await cloud.list(.of("owner-1"))

    let query = seen.value?.query ?? ""
    #expect(query.contains("limit=2000"))
    #expect(query.contains("&owner=owner-1"))
}

// ── streaming ──

@Test func streamAsksForTheRateAndTheShelf() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"url":"https://s3.example.com/x","kilobits":320}"#)
    }

    let got = try await cloud.stream(.of("owner-1"), rpmId: "rpm_1", kilobits: 320)
    #expect(got.kilobits == 320)
    #expect(got.url.absoluteString == "https://s3.example.com/x")
    #expect(seen.value?.path == "/cloud/stream/rpm_1")
    #expect((seen.value?.query ?? "").contains("rate=320"))
    #expect((seen.value?.query ?? "").contains("owner=owner-1"))
}

// ── playlists ──

/// The same trap as `list`: `cloud/playlists` is a borrowable route and its
/// envelope carries `owner` for exactly that reason.
@Test func aBorrowedPlaylistListingIsCheckedTheSameWay() async {
    let cloud = client(200, #"{"playlists":[],"owner":null}"#)
    await #expect(throws: RPMError.self) {
        _ = try await cloud.playlists(.of("someone-else"))
    }
}

@Test func ownPlaylistsNeedNoOwner() async throws {
    let cloud = client(200,
        #"{"playlists":[{"playlistId":"p1","name":"x","trackIds":[]}],"owner":null}"#)
    let lists = try await cloud.playlists(.own)
    #expect(lists.map(\.playlistId) == ["p1"])
}

/// A write against a stamp that has moved is refused, and **the refusal carries
/// the copy that is actually stored**. That copy is the whole reason the write is
/// made conditionally: the merge needs the other side, not a sentence about it.
@Test func aRefusedPlaylistWriteCarriesTheCopyThatIsStored() async {
    let cloud = client(409, #"{"playlistId":"p1","name":"Theirs","trackIds":["a","b"],"updatedAt":77}"#)
    do {
        _ = try await cloud.putPlaylist(
            CloudPlaylist(playlistId: "p1", name: "Mine", trackIds: []), ifUnchangedSince: 100)
        Issue.record("expected a throw")
    } catch let clash as PlaylistConflict {
        #expect(clash.name == "Mine", "the sentence names the copy that was being written")
        #expect(clash.stored?.trackIds == ["a", "b"])
        #expect(clash.stored?.updatedAt == 77)
    } catch {
        Issue.record("expected a PlaylistConflict, got \(error)")
    }
}

/// A store too old to answer with the stored copy leaves nothing to merge against,
/// which the caller has to be able to tell apart from a merge it can do.
@Test func aRefusalWithNoCopyInItSaysSo() async {
    let cloud = client(409, "")
    do {
        _ = try await cloud.putPlaylist(
            CloudPlaylist(playlistId: "p1", name: "Mine", trackIds: []), ifUnchangedSince: 100)
        Issue.record("expected a throw")
    } catch let clash as PlaylistConflict {
        #expect(clash.stored == nil)
    } catch {
        Issue.record("expected a PlaylistConflict, got \(error)")
    }
}

/// **The route this suite exists for.** The store names the collection in the
/// plural and the thing in the singular. A write sent to the listing's route with an
/// id on the end gets a 404 every time, and no decode test could see that.
@Test func aPlaylistIsWrittenToTheSingularRouteWithTheIdInThePath() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"updatedAt":5}"#)
    }

    _ = try await cloud.putPlaylist(
        CloudPlaylist(playlistId: "p 1/x", name: "n", trackIds: []), ifUnchangedSince: 0)

    #expect(seen.value?.absoluteString.hasSuffix("cloud/playlist/p%201%2Fx") == true,
            "wrote to \(seen.value?.absoluteString ?? "nowhere")")
}

@Test func removingAPlaylistGoesToTheSingularRouteToo() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, "")
    }

    try await cloud.deletePlaylist(id: "p1")
    #expect(seen.value?.absoluteString.hasSuffix("cloud/playlist/p1") == true)
}

/// Asking for something to be gone that is already gone is not a failure.
@Test func removingAPlaylistThatIsNotThereIsNotAnError() async throws {
    try await client(404, "").deletePlaylist(id: "p1")
}

// ── marks ──

@Test func markWritesGoToTheSingularRouteWithTheKeyInThePath() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"updatedAt":1756252800}"#)
    }

    let stamp = try await cloud.putAlbumMark(
        albumKey: "talk talk|laughing stock", favorite: true, favoritedUtcTicks: 638_000_000_000_000_000)

    #expect(stamp == 1_756_252_800)
    // absoluteString, not `path`: URL.path hands back the DECODED path, so an
    // assertion on it passes whether or not the key was ever escaped.
    #expect(seen.value?.absoluteString
        == "https://api.example.com/cloud/album-mark/talk%20talk%7Claughing%20stock")
}

/// Unmarking sends a zero stamp, not the current time. A row that says it was
/// favourited at a moment and also that it is not a favourite is a row two
/// clients will disagree about.
@Test func unmarkingSendsAZeroStamp() async throws {
    let body = Box<Data>()
    let cloud = client { request in
        body.value = request.bodyData
        return ok(request, #"{"updatedAt":1}"#)
    }

    _ = try await cloud.putAlbumMark(albumKey: "k", favorite: false, favoritedUtcTicks: 999)
    let sent = String(data: body.value ?? Data(), encoding: .utf8) ?? ""
    #expect(sent.contains("\"favoritedAt\":0"))
}

@Test func marksAreReadFromThePluralRoute() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"albums":[{"albumKey":"k","favorite":true,"updatedAt":2}]}"#)
    }
    let marks = try await cloud.albumMarks(.own)
    #expect(marks.count == 1)
    #expect(seen.value?.path == "/cloud/album-marks")
}

/// A borrowed shelf's marks are asked for under its owner, so its classical
/// records are drawn as works the way the owner's own copy is.
@Test func aBorrowedShelfsMarksAreAskedForUnderItsOwner() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"albums":[{"albumKey":"k","favorite":false,"updatedAt":2,"classical":true}],"owner":"friend"}"#)
    }

    let marks = try await cloud.albumMarks(.of("friend"))

    #expect(marks.first?.classical == true)
    #expect(seen.value?.absoluteString == "https://api.example.com/cloud/album-marks?owner=friend")
}

/// A store that predates `?owner=` answers a borrowed read with the caller's
/// OWN marks and a 200. Taken as the friend's, the caller's classical records
/// would be drawn as works on the friend's shelf.
@Test func aBorrowedReadAnsweredWithTheCallersOwnMarksIsRefused() async throws {
    let cloud = client { request in
        ok(request, #"{"albums":[{"albumKey":"k","favorite":true,"updatedAt":2}]}"#)
    }

    await #expect(throws: RPMError.self) {
        _ = try await cloud.albumMarks(.of("friend"))
    }
}

// ── favourites on a track ──

/// A track's mark is stored on its catalogue row, and the push is a merge at the far
/// end: what it does not mention is not touched.
@Test func settingATrackFavouritePushesOnlyThatField() async throws {
    let body = Box<Data>()
    let cloud = client { request in
        body.value = request.bodyData
        return ok(request, #"{"updated":1}"#)
    }

    try await cloud.setFavorite(rpmId: "rpm_1", favorite: true, favoritedUtcTicks: 42)
    let sent = String(data: body.value ?? Data(), encoding: .utf8) ?? ""
    #expect(sent.contains("\"rpmId\":\"rpm_1\""))
    #expect(sent.contains("\"favorite\":true"))
    #expect(sent.contains("\"favoritedAt\":42"))
    #expect(!sent.contains("\"title\""), "a push that names a title would blank it")
}

// ── head clips ──

@Test func headClipsComeBackAsDecodedBytes() async throws {
    let cloud = client(200, #"""
    {"clips":[{"rpmId":"a","audio":"AAEC"},{"rpmId":"b","audio":null}]}
    """#)
    let clips = try await cloud.headClips(["a", "b"])
    #expect(clips["a"] == Data([0, 1, 2]))
    #expect(clips["b"] == nil, "a clip with no audio is not a clip")
}

/// The server's own cap. Asking for more is a request that fails whole rather
/// than one that returns some.
@Test func headClipsAreAskedForInBatchesOfFifty() async throws {
    let calls = Box<Int>()
    let cloud = client { request in
        calls.value = (calls.value ?? 0) + 1
        return ok(request, #"{"clips":[]}"#)
    }
    _ = try await cloud.headClips((0..<120).map { "id-\($0)" })
    #expect(calls.value == 3)
}

@Test func askingForNoHeadClipsSendsNothing() async throws {
    let calls = Box<Int>()
    let cloud = client { request in
        calls.value = (calls.value ?? 0) + 1
        return ok(request, #"{"clips":[]}"#)
    }
    let clips = try await cloud.headClips([])
    #expect(clips.isEmpty)
    #expect(calls.value == nil)
}

// ── asking for renditions to be made ──

/// The store's names for the two fields, and the counts added up across pieces.
@Test func makingRenditionsSendsTheTracksAndTheRate() async throws {
    let body = Box<Data>()
    let seen = Box<URLRequest>()
    let cloud = client { request in
        body.value = request.bodyData
        seen.value = request
        return ok(request, #"{"kilobits":320,"ready":1,"queued":2}"#)
    }

    let said = try await cloud.makeRenditions(["a", "b", "c"], kilobits: 320)
    #expect(said.ready == 1)
    #expect(said.queued == 2)
    #expect(seen.value?.httpMethod == "POST")
    #expect(seen.value?.url?.path == "/cloud/transcode")

    let sent = String(data: body.value ?? Data(), encoding: .utf8) ?? ""
    #expect(sent.contains("\"rpmIds\":[\"a\",\"b\",\"c\"]"))
    #expect(sent.contains("\"kilobits\":320"))
}

/// The server refuses more than two hundred at once, whole.
@Test func makingRenditionsIsAskedInPiecesOfTwoHundred() async throws {
    let calls = Box<Int>()
    let cloud = client { request in
        calls.value = (calls.value ?? 0) + 1
        return ok(request, #"{"kilobits":256,"ready":0,"queued":1}"#)
    }
    let said = try await cloud.makeRenditions((0..<450).map { "id-\($0)" }, kilobits: 256)
    #expect(calls.value == 3)
    #expect(said.queued == 3)
}

@Test func makingNoRenditionsSendsNothing() async throws {
    let calls = Box<Int>()
    let cloud = client { request in
        calls.value = (calls.value ?? 0) + 1
        return ok(request, #"{}"#)
    }
    _ = try await cloud.makeRenditions([], kilobits: 320)
    #expect(calls.value == nil)
}

// ── the sidecar, which is two hops and a different casing ──

/// The sidecar is a blob the uploader wrote, not a Lambda response, so it is
/// PascalCase where the whole rest of this API is camelCase.
@Test func theSidecarDecodesItsPascalCaseFields() throws {
    let sidecar = try fixture("sidecar", as: TagSidecar.self)
    #expect(sidecar.title == "Myrrhman")
    #expect(sidecar.album == "Laughing Stock")
    #expect(sidecar.relativePath.hasSuffix("Myrrhman.flac"))
    #expect(sidecar.artMime == "image/jpeg")
    #expect((sidecar.art?.count ?? 0) > 0)
}

/// Two hops: the store signs a URL, and the bytes come from S3. The second hop
/// must carry NO bearer. A presigned URL is signed for exactly the request it
/// describes, and an extra Authorization header is a different request.
@Test func theSidecarSecondHopSendsNoBearer() async throws {
    let secondHop = Box<URLRequest>()
    let calls = Box<Int>()
    let sidecarJson = try String(data: fixtureData("sidecar"), encoding: .utf8) ?? "{}"

    let cloud = client { request in
        let n = (calls.value ?? 0) + 1
        calls.value = n
        if n == 1 { return ok(request, #"{"url":"https://s3.example.com/sidecar.json"}"#) }
        secondHop.value = request
        return ok(request, sidecarJson)
    }

    let sidecar = try await cloud.sidecar(rpmId: "rpm_1")
    #expect(sidecar?.title == "Myrrhman")
    #expect(secondHop.value?.url?.host == "s3.example.com")
    #expect(secondHop.value?.value(forHTTPHeaderField: "Authorization") == nil)
}

/// A track with no sidecar is a track with no sidecar, not an error. The phone
/// falls through to its artwork lookup, which is the whole point of asking.
@Test func aMissingSidecarIsNilRatherThanAThrow() async throws {
    let cloud = client(404, "{}")
    #expect(try await cloud.sidecar(rpmId: "rpm_1") == nil)
}

// ── account ──

@Test func devicesSharesAndQuotaRead() async throws {
    #expect(try await client(200, #"{"usedBytes":1,"quotaBytes":2,"fileCount":3}"#)
        .quota().fileCount == 3)
    #expect(try await client(200, #"{"devices":[{"deviceId":"d1","publicKey":"k","name":"n"}]}"#)
        .devices().count == 1)
    #expect(try await client(200, #"{"granted":[],"received":[]}"#)
        .shares().granted.isEmpty)
}

/// **A listing that failed is not a collection with no covers in it.** If this route
/// swallowed its errors and answered with an empty list, the artwork store could not
/// tell the two apart, and either answer it picked would be wrong for the other case:
/// trust the empty list and a phone in a tunnel draws placeholders over a disk full of
/// sleeves, distrust it and an account that genuinely has none asks again once per
/// record for ever.
@Test func anArtIndexThatCouldNotBeReadSaysSo() async {
    await #expect(throws: RPMError.self) { _ = try await client(500, "{}").artCatalog(.own) }
}

@Test func aCollectionWithNoCoversIsAnEmptyListing() async throws {
    #expect(try await client(200, #"{"albums":[]}"#).artCatalog(.own).isEmpty)
}

/// A cover asked for at an edge carries `size`, which is what makes the API sign its cut copy
/// instead of the original.
@Test func aCoverAskedForAtAnEdgeSendsTheSize() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"url":"https://s3.example.com/c","updatedAt":7}"#)
    }

    let got = await cloud.art(.own, albumKey: "k1", size: .edge(1024))
    #expect(got?.url == "https://s3.example.com/c")
    #expect(got?.updatedAt == 7)
    #expect(seen.value?.path == "/cloud/art/k1")
    #expect(seen.value?.query == "size=1024")
}

/// The original is asked for with no `size` at all.
@Test func theOriginalIsAskedForWithoutASize() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"url":"https://s3.example.com/c","updatedAt":7}"#)
    }

    _ = await cloud.art(.own, albumKey: "k1", size: .original)
    #expect(seen.value?.path == "/cloud/art/k1")
    #expect(seen.value?.query == nil)
}

/// A borrowed shelf's owner opens the query, so the size follows it with `&`.
@Test func aBorrowedCoverSendsTheOwnerThenTheSize() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"url":"https://s3.example.com/c","updatedAt":7}"#)
    }

    _ = await cloud.art(.of("owner-1"), albumKey: "k1", size: .edge(512))
    #expect(seen.value?.query == "owner=owner-1&size=512")
}

// ── measured lyric timing ──

/// A track's measured word timing is read from its route, under its shelf.
@Test func aTracksMeasuredLyricsAreReadUnderItsShelf() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"""
            {"lines":[{"index":0,"seconds":1.5,"text":"hi you","words":[{"from":1.6,"to":1.9},{"from":2.0,"to":2.3}]}],
             "owner":"owner-1"}
            """#)
    }

    let lines = try await cloud.lyricTiming(rpmId: "rpm_1", on: .of("owner-1"))
    #expect(lines.count == 1)
    #expect(lines[0].words.map(\.from) == [1.6, 2.0])
    #expect(seen.value?.path == "/cloud/lyric-timing/rpm_1")
    #expect(seen.value?.query == "owner=owner-1")
}

/// A track nobody has measured is no measurement, not a failure.
@Test func aTrackNobodyMeasuredHasNoLines() async throws {
    #expect(try await client(404, "{}").lyricTiming(rpmId: "rpm_1", on: .own).isEmpty)
}

/// The sheet goes to the measure route, line by line with its place and moment.
@Test func aMeasurementIsAskedForWithTheSheet() async throws {
    let seen = Box<URLRequest>()
    let cloud = client { request in
        seen.value = request
        return ok(request, "{}")
    }

    try await cloud.measureLyrics(rpmId: "rpm_1", on: .own,
                                  lines: [SheetLine(index: 0, seconds: 1.5, text: "hi you")])
    #expect(seen.value?.url?.path == "/cloud/lyric-timing/rpm_1/measure")
    #expect(seen.value?.httpMethod == "POST")
}

// ── a shared library's saved stations ──

/// A shared library's saved stations are asked of its owner, all of them.
@Test func aSharedLibrarysSavedStationsAreAskedOfItsOwner() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"""
            {"stations":[{"uuid":"s1","saved":true,"changedAt":5,"station":null,"updatedAt":9}],
             "owner":"owner-1"}
            """#)
    }

    let rows = try await cloud.stationFavorites(of: .of("owner-1"))
    #expect(rows.map(\.uuid) == ["s1"])
    #expect(seen.value?.path == "/cloud/station-favorites")
    #expect(seen.value?.query == "since=0&owner=owner-1")
}

/// An answer that names another owner (a server that ignores `owner=` sends the caller's own) is
/// refused, as every borrowed read's is.
@Test func savedStationsAnsweredForAnotherOwnerAreRefused() async {
    let cloud = client(200, #"{"stations":[],"owner":"me"}"#)
    await #expect(throws: RPMError.self) {
        _ = try await cloud.stationFavorites(of: .of("owner-1"))
    }
}

// ── what this listener has played ──

/// An envelope, not a bare array, and every field but the id survives being absent: these
/// rows outlive the shape they were written in.
@Test func playRowsReadBackWithTheDeviceThatPlayedThem() async throws {
    let rows = try await client(200, #"""
        {"tracks":[{"rpmId":"t1","deviceId":"desk","plays":4,"lastPlayedAt":900,"updatedAt":10}]}
        """#).trackPlays()

    #expect(rows.count == 1)
    #expect(rows[0].deviceId == "desk")
    #expect(rows[0].plays == 4)
    #expect(rows[0].updatedAt == 10)
}

@Test func playRowsSurviveMissingFields() async throws {
    let rows = try await client(200, #"{"tracks":[{"rpmId":"t1"}]}"#).trackPlays()

    #expect(rows[0].rpmId == "t1")
    #expect(rows[0].plays == 0)
    #expect(rows[0].deviceId == "")
}

@Test func aListingWithNoPlaysIsEmptyRatherThanAFailure() async throws {
    #expect(try await client(200, #"{"tracks":[]}"#).trackPlays().isEmpty)
}

/// The cursor goes on the wire, so a phone that has taken everything up to a stamp does not
/// ask for the whole history on every launch.
@Test func theCursorIsAskedFor() async throws {
    let asked = Box<String>()
    let cloud = client { request in
        asked.value = request.url?.absoluteString ?? ""
        return ok(request, #"{"tracks":[]}"#)
    }

    _ = try await cloud.trackPlays(since: 4242)

    #expect(asked.value?.contains("since=4242") == true)
}

/// The listing as the service writes it, nulls included: ASP.NET's defaults, and the field
/// names `CloudStationListensTests.The_listing_uses_the_names_the_clients_decode` pins.
@Test func stationRowsReadBackWithTheDeviceAndTheStation() async throws {
    let rows = try await client(200, #"""
        {"stations":[{"uuid":"s1","deviceId":"desk","heardSeconds":612.5,"tunes":3,"lastHeardAt":99,
        "station":{"uuid":"s1","name":"Radio One","streamUrl":"https://streams.example/s1.mp3",
        "homepage":null,"favicon":"https://streams.example/logo.png","country":null,"countryCode":"NL",
        "language":null,"tags":["pop","news"],"codec":"MP3","bitrateKbps":128,"isHls":false},
        "updatedAt":1700000001}]}
        """#).stationListens()

    #expect(rows.count == 1)
    #expect(rows[0].deviceId == "desk")
    #expect(rows[0].heardSeconds == 612.5)
    #expect(rows[0].tunes == 3)
    #expect(rows[0].updatedAt == 1700000001)
    #expect(rows[0].station?.name == "Radio One")
    #expect(rows[0].station?.homepage == nil)
    #expect(rows[0].station?.tags == ["pop", "news"])
}

/// A row whose station will not decode is kept as a row with no station, so the rest of the
/// listing still arrives and the cursor still moves past it.
@Test func aStationThatWillNotDecodeDoesNotSinkTheListing() async throws {
    let rows = try await client(200, #"""
        {"stations":[{"uuid":"s1","deviceId":"desk","heardSeconds":60,"tunes":1,"lastHeardAt":1,
        "station":{"uuid":"s1"},"updatedAt":5},
        {"uuid":"s2","deviceId":"desk","heardSeconds":60,"tunes":1,"lastHeardAt":1,
        "station":{"uuid":"s2","name":"Two","streamUrl":"https://example/2"},"updatedAt":6}]}
        """#).stationListens()

    #expect(rows.count == 2)
    #expect(rows[0].station == nil)
    #expect(rows[1].station?.name == "Two")
}

@Test func sendingStationListensAnswersWithTheStamp() async throws {
    let station = CloudListenedStation(uuid: "s1", name: "One", streamUrl: "https://example/1",
                                       homepage: nil, favicon: nil, country: nil, countryCode: nil,
                                       language: nil, tags: [], codec: nil, bitrateKbps: 0, isHls: false)
    let stamp = try await client(200, #"{"updatedAt":78}"#)
        .sendStationListens(deviceId: "phone",
                            rows: [StationListensEntry(uuid: "s1", heardSeconds: 60, tunes: 1,
                                                       lastHeardAt: 5, station: station)])

    #expect(stamp == 78)
}

@Test func sendingPlaysAnswersWithTheStampTheyWereWrittenUnder() async throws {
    let stamp = try await client(200, #"{"updatedAt":77}"#)
        .sendTrackPlays(deviceId: "phone",
                        rows: [TrackPlaysEntry(rpmId: "t1", plays: 2, lastPlayedAt: 5)])

    #expect(stamp == 77)
}
