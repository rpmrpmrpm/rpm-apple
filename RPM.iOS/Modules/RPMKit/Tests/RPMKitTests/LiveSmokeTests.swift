import Testing
import Foundation
@testable import RPMKit

/// Fixtures prove the Swift decodes what was captured. Only this proves the
/// service still sends it.
///
/// Off unless credentials are in the environment, so an ordinary `swift test`
/// stays offline and fast. Run it deliberately:
///
///     RPM_TEST_EMAIL=… RPM_TEST_PASSWORD=… swift test --filter LiveSmoke
///
/// **Read-only.** It signs in, reads, and asks for a stream URL without fetching
/// a byte of audio. It writes nothing: a smoke test that writes is a smoke test
/// that leaves rows behind in a real account.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_EMAIL"] != nil))
struct LiveSmokeTests {
    static let accounts = URL(string: "https://accounts.rpmrpmrpm.com/")!
    static let api = URL(string: "https://api.rpmrpmrpm.com")!

    private func signedIn() async throws -> (AuthClient, RPMCloudClient, RPMCommunityClient) {
        let env = ProcessInfo.processInfo.environment
        let auth = AuthClient(base: Self.accounts, keychain: MemoryStore(), reach: NetworkReach())
        try await auth.signIn(email: env["RPM_TEST_EMAIL"]!,
                              password: env["RPM_TEST_PASSWORD"]!)

        let transport = Transport(base: Self.api, tokens: auth, reach: NetworkReach())
        return (auth, RPMCloudClient(transport: transport), RPMCommunityClient(transport: transport))
    }

    // ── the accounts service ──

    @Test func signsInAgainstTheRealAccountsService() async throws {
        let (auth, _, _) = try await signedIn()
        #expect(await auth.isSignedIn)
        #expect(try await auth.accessToken() != nil)
        #expect(await auth.current?.userId.isEmpty == false)
    }

    @Test func aWrongPasswordIsRefusedWithASentence() async {
        let env = ProcessInfo.processInfo.environment
        let auth = AuthClient(base: Self.accounts, keychain: MemoryStore(), reach: NetworkReach())
        do {
            try await auth.signIn(email: env["RPM_TEST_EMAIL"]!, password: "not-the-password")
            Issue.record("expected a throw")
        } catch let error as RPMError {
            guard case .refused(status: 401, reason: .wrongPassword) = error else {
                Issue.record("expected a wrong password, got \(error)")
                return
            }
        } catch {
            Issue.record("expected an RPMError, got \(error)")
        }
    }

    /// The half of social sign-in that can break without anybody noticing: the
    /// accounts service handing back somewhere to send the person and a row to watch.
    ///
    /// Only the first half. Finishing it needs a human and a Google password, and a
    /// test that could do that would be a test holding one.
    @Test func socialSignInHandsBackSomewhereToSendThePerson() async throws {
        let auth = AuthClient(base: Self.accounts, keychain: MemoryStore(), reach: NetworkReach())

        for provider in ["Google", "Apple"] {
            let (url, sessionId) = try await auth.startSocialSignIn(provider: provider)

            #expect(url.scheme == "https", "\(provider) came back with \(url)")
            #expect(!sessionId.isEmpty)

            // Nothing has happened on that row yet, so the poll finds nothing and
            // gives up rather than reporting a sign-in.
            await #expect(throws: RPMError.self) {
                try await auth.pollSocial(sessionId: sessionId,
                                          every: .milliseconds(200),
                                          giveUpAfter: .milliseconds(600))
            }
            #expect(await !auth.isSignedIn)
        }
    }

    // ── the cloud ──

    @Test func quotaDecodesFromTheRealStore() async throws {
        let (_, cloud, _) = try await signedIn()
        let quota = try await cloud.quota()
        #expect(quota.quotaBytes > 0)
    }

    /// The listing is the shape most likely to drift, because it is the one the
    /// desktop keeps adding catalogue fields to. The smoke account holds one album
    /// so that this can assert on rows rather than only on the envelope.
    @Test func theCatalogDecodesFromTheRealStore() async throws {
        let (_, cloud, _) = try await signedIn()
        let tracks = try await cloud.list(.own)

        #expect(!tracks.isEmpty, "the smoke account has no music in it, so this proves nothing")
        #expect(tracks.contains { $0.tags != nil }, "no row carried catalog tags")

        let tagged = try #require(tracks.first { $0.tags?.hasFormat == true })
        #expect(tagged.duration > .zero)
        #expect(tagged.tags?.sampleRate ?? 0 > 0)
        #expect(UUID(uuidString: tagged.rpmId) != nil, "an rpmId should be a bare GUID")
    }

    /// A cursor-paged read of a real library, asked for in pages of one so the
    /// paging actually runs. A client that ignored the cursor would answer with
    /// the first page and look perfectly healthy.
    @Test func theCatalogPagesThroughItsCursor() async throws {
        let (auth, _, _) = try await signedIn()
        let transport = Transport(base: Self.api, tokens: auth, reach: NetworkReach())

        var seen: [String] = []
        var cursor: String?
        var pages = 0

        repeat {
            var path = "cloud/list?limit=1"
            if let cursor { path += "&cursor=" + cursor }
            let page = try await transport.get(path, as: CloudListPage.self)
            seen.append(contentsOf: page.files.map(\.rpmId))
            cursor = page.cursor
            pages += 1
        } while cursor != nil && pages < 40

        #expect(pages > 1, "the store served a whole library in one page of one")
        #expect(Set(seen).count == seen.count, "a row came back on two pages")
    }

    /// A signed URL for a track that is really there, without fetching a byte of
    /// it. The rate the store answers with is not always the rate asked for.
    @Test func aStreamUrlIsSignedForARealTrack() async throws {
        let (_, cloud, _) = try await signedIn()
        let first = try #require(try await cloud.list(.own).first)

        let got = try await cloud.stream(.own, rpmId: first.rpmId, kilobits: 320)
        #expect(got.url.scheme == "https")
        #expect(got.kilobits > 0)
    }

    /// Two hops and a different casing, against the real store. This is the one
    /// that would have failed silently: the sidecar is PascalCase and the second
    /// hop must carry no bearer.
    @Test func aRealSidecarDecodesOverTwoHops() async throws {
        let (_, cloud, _) = try await signedIn()
        let first = try #require(try await cloud.list(.own).first)

        let sidecar = try #require(await cloud.sidecar(rpmId: first.rpmId))
        #expect(!sidecar.relativePath.isEmpty)
        #expect(sidecar.extension == ".flac")
        #expect(sidecar.durationSeconds > 0)
    }

    /// The head clips the upload made as its last step.
    @Test func headClipsComeBackForRealTracks() async throws {
        let (_, cloud, _) = try await signedIn()
        let ids = try await cloud.list(.own).prefix(5).map(\.rpmId)

        let clips = try await cloud.headClips(Array(ids))
        #expect(clips.values.allSatisfy { !$0.isEmpty }, "a clip came back empty")
    }

    /// The art index, with a cover actually in it, so the shape that has two
    /// spellings is exercised on the one that carries stamps.
    @Test func theArtIndexCarriesARealCover() async throws {
        let (_, cloud, _) = try await signedIn()
        let covers = try await cloud.artCatalog(.own)
        #expect(!covers.isEmpty, "the smoke account has no cover stored")

        let key = try #require(covers.first).albumKey
        let one = await cloud.art(.own, albumKey: key, size: .original)
        #expect(one?.url?.isEmpty == false)
    }

    /// A shelf nobody has shared must not come back as this account's own rows.
    /// The check is the point; a store that serves it anyway is the bug the
    /// check exists for.
    @Test func aShelfThatWasNeverSharedIsNotServed() async throws {
        let (_, cloud, _) = try await signedIn()
        await #expect(throws: RPMError.self) {
            _ = try await cloud.list(.of("00000000-0000-4000-8000-000000000000"))
        }
    }

    @Test func playlistsMarksAndArtDecodeFromTheRealStore() async throws {
        let (_, cloud, _) = try await signedIn()
        _ = try await cloud.playlists(.own)
        _ = try await cloud.albumMarks(.own)
        _ = try await cloud.artCatalog(.own)
    }

    /// The envelope these arrive in is a dictionary, not an array. Only the live
    /// service shows that.
    @Test func devicesAndSharesDecodeFromTheRealStore() async throws {
        let (_, cloud, _) = try await signedIn()
        _ = try await cloud.devices()
        _ = try await cloud.shares()
    }

    // ── the wall ──

    @Test func theProfileDecodesFromTheRealService() async throws {
        let (auth, _, community) = try await signedIn()
        let profile = try await community.profile()
        #expect(profile.userId == (await auth.current?.userId))
        #expect(!profile.displayName.isEmpty)

        // Milliseconds. A fresh account stamped in seconds would read as 1970.
        #expect(profile.createdAt > 1_000_000_000_000)
    }

    /// The route every shared library's name comes off. Asked against the account's
    /// own id, which is the one id a test can be sure exists.
    @Test func somebodyElsesProfileIsReadFromTheRealService() async throws {
        let (auth, _, community) = try await signedIn()
        let me = await auth.current?.userId ?? ""

        let said = try await community.publicProfile(userId: me)
        #expect(said?.displayName == (try await community.profile()).displayName)
    }

    /// An id nobody has ever had. The service says so with a 404, and a client that
    /// let that throw would call an ordinary answer an outage and stop asking.
    @Test func anIdWithNoProfileBehindItIsNilFromTheRealService() async throws {
        let (_, _, community) = try await signedIn()
        #expect(try await community.publicProfile(userId: "nobody-has-this-id") == nil)
    }

    // ── the words ──

    /// LRCLIB, which is not RPM's service and is asked for nothing but a User-Agent.
    /// Here rather than in the offline suite because what this proves is that the
    /// service still answers in the shape the parser reads.
    @Test func aRecordsWordsComeBackTimedFromLrcLib() async throws {
        let sheet = await LrcLibClient(reach: openLine()).sheet(
            artist: "Enya", title: "Orinoco Flow",
            album: "The Very Best of Enya", duration: 266)

        #expect(sheet.isSynced, "no synced sheet came back")
        #expect(sheet.lines.count > 20)
        #expect(sheet.lines.contains { $0.text.contains("Orinoco") })

        // In time order, and starting somewhere sensible rather than at zero.
        #expect(sheet.lines == sheet.lines.sorted { $0.seconds < $1.seconds })
        #expect(sheet.lines.last?.seconds ?? 0 > 60)
    }

    /// A record nobody has written down. **The answer is no sheet, not a failure**.
    /// Every screen treats the two the same way and a caller must not have to tell them
    /// apart.
    @Test func aRecordNobodyHasWrittenDownIsNoSheet() async {
        let sheet = await LrcLibClient(reach: openLine()).sheet(
            artist: "An Artist That Does Not Exist",
            title: "A Record That Does Not Exist", album: nil, duration: 123)

        #expect(!sheet.isSynced)
    }

    // ── the papers ──

    /// The RPM API's papers, then Wikidata and Wikipedia. Signed out, as the album page asks for
    /// them: the app key is enough. What this proves is that the three services still answer in
    /// the shapes ``Encyclopedia`` reads.
    private func papers() -> PapersClient {
        let transport = Transport(base: Self.api, tokens: FixedTokens(token: nil), reach: openLine())
        return PapersClient(transport: transport, reach: openLine())
    }

    @Test func aRecordsArticleComesBackInTheReadersLanguage() async throws {
        let article = try await papers().albumArticle(
            artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["nl", "en"]).article

        #expect(article?.language == "nl")
        #expect(article?.url.hasPrefix("https://nl.wikipedia.org/") == true)
        #expect((article?.extract.count ?? 0) > 100)
    }

    @Test func anActsArticleComesBackUnderTheirNameAlone() async throws {
        let article = try await papers().artistArticle(artist: "Harry Styles", languages: ["en"]).article

        #expect(article?.language == "en")
        #expect(article?.title == "Harry Styles")
        #expect((article?.paragraphs.count ?? 0) > 1)
    }

    @Test func searchingTheWallDecodes() async throws {
        let (_, _, community) = try await signedIn()
        _ = try await community.searchAlbums("talk talk", limit: 3)
    }

    /// Nobody having written about a record is the usual answer, and the service
    /// says it with a 404. A client that let that throw would put an error on
    /// every album page in a new library.
    @Test func lookingUpARecordNobodyHasWrittenAboutIsNilRatherThanAThrow() async throws {
        let (_, _, community) = try await signedIn()
        let found = await community.lookupAlbum(
            artist: "An Artist That Does Not Exist", title: "A Record That Does Not Exist")
        #expect(found == nil)
    }
}

// ── RPM's radio record ──

extension LiveSmokeTests {
    /// With the app key alone, as a phone that is not signed in asks: both endpoints are public
    /// reads, and through ``Transport`` so the call is the one the app makes.
    private func radio() -> RadioRepositoryClient {
        RadioRepositoryClient(transport: Transport(base: Self.api, tokens: FixedTokens(token: nil),
                                                   reach: NetworkReach()))
    }

    @Test func theRadioStateIsReadable() async throws {
        let state = try await radio().state(.pastTheStore)
        // Nothing to assert about the content, which is the admin's; that it decodes is the point.
        _ = state.hidden.count
    }

    /// NPO Radio 1's main stream, for which the crawl has settled a logo.
    @Test func aStationTheCrawlSettledHasALogo() async throws {
        let state = try await radio().state(.stored)
        let logo = try await radio().logo(station: "96126f56-0601-11e8-ae97-52543be04c81",
                                          stamp: state.logos)

        guard case .found(let data) = logo else {
            Issue.record("expected a logo, got \(logo)")
            return
        }
        #expect(data.count > 100)
    }
}
