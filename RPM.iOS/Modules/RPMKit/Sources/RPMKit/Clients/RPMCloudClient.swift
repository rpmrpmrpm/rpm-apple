import Foundation

/// Everything the phone asks of the cloud.
///
/// A thin struct over `Transport`: the routes, their shapes, and the two rules
/// that cannot live at a call site. Nothing is cached here. What to keep and for
/// how long is decided by `RPMLibrary`. If both places decided it, two caches
/// could disagree.
public struct RPMCloudClient: Sendable {
    private let transport: Transport

    public init(transport: Transport) { self.transport = transport }

    // ── the catalogue ──

    /// Every track on a shelf, following the cursor.
    ///
    /// The request asks for the largest pages that the API will serve. The server clamps the
    /// limit, and DynamoDB caps a page at one megabyte in any case, so a smaller page is
    /// normal. The cursor decides whether to ask again. The limit only changes how many
    /// sequential round trips a whole library needs.
    ///
    /// `onProgress` is told the running row count after every page, so a caller with a screen
    /// can show progress. A library is about twenty round trips at most, and the only
    /// progress that can be reported is how many rows have arrived.
    public func list(
        _ shelf: CloudShelf,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async throws -> [CloudTrack] {
        var all: [CloudTrack] = []
        var cursor: String?

        repeat {
            var path = "cloud/list?limit=2000" + shelf.query(first: false)
            if let cursor {
                path += "&cursor=" + escaped(cursor)
            }

            let page = try await transport.get(path, as: CloudListPage.self)

            // Check whose rows these are before any row is kept. A server that does not know
            // about shared collections answers a borrowed listing with the caller's own rows
            // and a 200 status. The client would then work on the wrong library without any
            // error.
            if !shelf.isOwn && page.owner != shelf.ownerId {
                throw RPMError.notServed(ownerId: shelf.ownerId)
            }

            all.append(contentsOf: page.files)
            cursor = page.cursor
            onProgress?(all.count)
        } while cursor != nil

        return all
    }

    /// Writes what the client knows onto its own cloud rows.
    ///
    /// The server merges the push: what a push does not mention is not changed, and
    /// a blank means "not being changed", not "make it empty". For this reason
    /// `setFavorite` sends a `CloudTrackTags` that carries only the mark.
    @discardableResult
    public func pushCatalog(_ rows: [CatalogPush]) async throws -> Int {
        guard !rows.isEmpty else { return 0 }

        struct Body: Encodable { let items: [CatalogPush] }
        struct Said: Decodable { let updated: Int? }

        var updated = 0
        // A page of one hundred keeps one request inside a Lambda's time limit however
        // slow the table is. This matches the server's own batch size.
        for batch in rows.chunked(100) {
            let said = try await transport.send(
                "POST", "cloud/catalog/tags", body: Body(items: batch), as: Said.self)
            updated += said.updated ?? 0
        }
        return updated
    }

    /// The listener's mark on one song, which rides on its catalogue row.
    ///
    /// Unmarking sends a zero stamp and not the current time. A row that says both that it was
    /// favourited at a moment and that it is not a favourite could be read in two ways, and
    /// two clients could disagree about it.
    public func setFavorite(rpmId: String, favorite: Bool, favoritedUtcTicks: Int64) async throws {
        var tags = CloudTrackTags()
        tags.favorite = favorite
        tags.favoritedAt = favorite ? favoritedUtcTicks : 0
        try await pushCatalog([CatalogPush(rpmId: rpmId, tags: tags)])
    }

    // ── streaming ──

    /// Where to stream from, and at what rate it is actually being served.
    ///
    /// The rate that is served can differ from the rate asked for. A free account is capped,
    /// and a rendition that has not been made yet falls back to another rate, so that nobody
    /// waits for a transcode. The caller needs the served rate to explain the sound quality.
    ///
    /// The grant behind a borrowed shelf is checked when the URL is signed, not once at
    /// pairing. A share that is taken back stops the music at the next track and not at the
    /// end of the hour.
    public func stream(
        _ shelf: CloudShelf, rpmId: String, kilobits: Int
    ) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        let said = try await transport.get(
            "cloud/stream/\(escaped(rpmId))?rate=\(kilobits)" + shelf.query(first: false),
            as: UrlResponse.self)

        guard let url = URL(string: said.url) else {
            throw RPMError.decoding(URLError(.badURL))
        }
        return (url, said.kilobits ?? kilobits, said.live == true ? .live : .stored)
    }

    /// The opening seconds of each track, so a wall can sound like something
    /// before anything is streamed.
    ///
    /// The requests are batched at the server's own cap. A request for more fails
    /// completely and does not return some of the clips.
    public func headClips(_ rpmIds: [String]) async throws -> [String: Data] {
        guard !rpmIds.isEmpty else { return [:] }

        struct Body: Encodable { let rpmIds: [String] }

        var clips: [String: Data] = [:]
        for batch in rpmIds.chunked(Self.mostHeadClips) {
            let said = try await transport.send(
                "POST", "cloud/heads", body: Body(rpmIds: batch), as: HeadClipsResponse.self)

            for clip in said.clips ?? [] {
                guard let audio = clip.audio, !audio.isEmpty else { continue }
                clips[clip.rpmId] = audio
            }
        }
        return clips
    }

    /// How many head clips may be asked for at once. This is the server's own cap.
    public static let mostHeadClips = 50

    /// Asks the store to make these tracks at a rate, and answers once the ask is on its work
    /// list. Nothing is made here. The store starts the transcoder, which makes them in
    /// the background.
    ///
    /// A stream that finds no rendition is given a live encode and queues nothing, because
    /// the live pass files what it made. Anything that needs the stored object and not the
    /// live one (a download) has to ask for it with this method.
    ///
    /// The request is sent in pieces of ``mostTranscodeTracks``, the server's own cap.
    ///
    /// - Returns: how many can already be served at that rate, and how many were put on the
    ///   work list. Tracks that are not this account's are skipped by the store and counted
    ///   in neither.
    @discardableResult
    public func makeRenditions(_ rpmIds: [String], kilobits: Int) async throws
        -> (ready: Int, queued: Int)
    {
        guard !rpmIds.isEmpty else { return (0, 0) }

        struct Body: Encodable { let rpmIds: [String]; let kilobits: Int }

        var ready = 0
        var queued = 0
        for batch in rpmIds.chunked(Self.mostTranscodeTracks) {
            let said = try await transport.send(
                "POST", "cloud/transcode", body: Body(rpmIds: batch, kilobits: kilobits),
                as: TranscodeResponse.self)
            ready += said.ready ?? 0
            queued += said.queued ?? 0
        }
        return (ready, queued)
    }

    /// How many tracks one transcode ask may name. This is the server's own cap.
    public static let mostTranscodeTracks = 200

    // ── the sidecar ──

    /// A track's own tags and embedded cover, in two hops.
    ///
    /// The store signs a URL and the bytes come from S3 without authentication: see
    /// `Transport.unauthenticated`. A track with no sidecar gives nil and does not throw,
    /// because the caller then continues with its artwork lookup, and a missing sidecar is the
    /// case that lookup handles.
    public func sidecar(rpmId: String) async throws -> TagSidecar? {
        let signed: UrlResponse
        do {
            signed = try await transport.get("cloud/sidecar/\(escaped(rpmId))", as: UrlResponse.self)
        } catch RPMError.refused {
            // Any refusal, a 404 or not, means "not there" for a caller that looks for
            // artwork.
            return nil
        }

        guard let url = URL(string: signed.url) else { return nil }
        return try? await transport.unauthenticated(url, as: TagSidecar.self)
    }

    // ── the generated lists ──

    /// The generated lists as a computer last produced them, or nil when it never did.
    ///
    /// **The phone shows these lists; it does not compute them.** The calculation uses
    /// percentiles over a whole collection, and it can change. If it were written once on the
    /// computer and once here, the two versions could drift apart, and nobody would see it
    /// until the same list held different records on the two screens. The computer is also the
    /// only app that has the whole collection. This app knows the tracks in the cloud and
    /// nothing about records that never left the computer's disk.
    ///
    /// Nil is an ordinary answer and not a failure: when the collection's computer has not
    /// produced lists yet, there is nothing to show. The lists that come back cover the
    /// computer's whole shelf, so this phone will not hold every record in them. It plays what
    /// it can resolve and skips the rest.
    /// - Parameter shelf: whose lists. A borrowed shelf is a whole collection, and the
    ///   way its owner arranged it is part of it. What can be played from it is a
    ///   different question and is answered at play time: over the network only the
    ///   records that the owner put in the cloud resolve, so a borrowed list is
    ///   shorter here than it is on the owner's own network.
    public func moodLists(_ shelf: CloudShelf = .own) async throws -> CloudMoodLists? {
        do {
            return try await transport.get(
                "cloud/moodlists" + shelf.query(first: true), as: CloudMoodLists.self)
        } catch RPMError.refused(status: 404, _) {
            return nil
        }
    }

    /// Where a playlist's own picture can be fetched from, signed, or nil where the
    /// store has none for it.
    ///
    /// **The result is the finished picture, not a recipe to draw it.** A generated list has one
    /// of eight drawn figures in colours chosen for what the list means. A playlist that a user
    /// made has the picture that the user chose for it, for example four records or an image from
    /// their disk. The computer draws all of these once, with Skia, using the app's own palette.
    /// This app has no such drawing code. Without the picture, a list would fall back to the
    /// sleeve of the record it opens on, and a list such as "Adrenaline" would show an
    /// unrelated album cover.
    ///
    /// Nil is the ordinary answer, not a failure: a playlist on the automatic cover
    /// uploads nothing, and a computer that has not uploaded list pictures has sent none.
    ///
    /// - Parameters:
    ///   - shelf: whose picture. A borrowed shelf's lists use their owner's pictures,
    ///     and the store checks the same grant that it checks for their music.
    ///   - playlistId: the list's own id: a stored playlist's cloud id, or the id that a
    ///     generated list carries in the lists from the computer.
    public func playlistArt(_ shelf: CloudShelf, playlistId: String) async -> URL? {
        do {
            let found = try await transport.get(
                "cloud/playlist-art/\(escaped(playlistId))" + shelf.query(first: true),
                as: UrlResponse.self)

            return URL(string: found.url)
        } catch {
            // Every failure here means "no picture". Artwork is decoration and never causes an
            // error on a screen. The rest of the art path follows the same rule.
            return nil
        }
    }

    // ── playlists ──

    /// A shelf's playlists, checked to be that shelf's.
    ///
    /// The same trap as in `list`: an older store ignores an `?owner=` that it does not know
    /// and answers with the caller's own lists and a 200 status.
    public func playlists(_ shelf: CloudShelf) async throws -> [CloudPlaylist] {
        let answer = try await transport.get(
            "cloud/playlists" + shelf.query(first: true), as: CloudPlaylistsResponse.self)

        if !shelf.isOwn && answer.owner != shelf.ownerId {
            throw RPMError.notServed(ownerId: shelf.ownerId)
        }
        return answer.playlists
    }

    /// Writes a playlist, refusing if it has moved since it was read.
    ///
    /// `ifUnchangedSince` makes it safe for two phones to edit one list. Without
    /// it, both phones write the whole list and the later write wins completely. **It has no
    /// default value.** An unconditional write can lose the user's work, so it must never
    /// happen by leaving an argument off.
    ///
    /// The route for a write is `cloud/playlist` and the route for the listing is
    /// `cloud/playlists`. One letter is the difference between a write and a 404: the store
    /// names the collection in the plural and a single item in the singular.
    ///
    /// This method makes its own request and does not use `send`, for one reason. A refusal
    /// here is an **answer**, because it carries the copy that is stored. `send` turns
    /// every response that is not a success into an error and discards the body.
    ///
    /// - Returns: the time that the store stamped on the playlist, in unix milliseconds from
    ///   the server's clock. A store that is too old to send a stamp gives zero, which means
    ///   "cannot tell".
    @discardableResult
    public func putPlaylist(
        _ playlist: CloudPlaylist, ifUnchangedSince: Int64?
    ) async throws -> Int64 {
        struct Body: Encodable {
            let name: String
            let trackIds: [String]
            let folder: [String]
            let ifUnchangedSince: Int64?
        }
        struct Said: Decodable { let updatedAt: Int64? }

        let (status, data) = try await transport.raw(
            "PUT", "cloud/playlist/\(escaped(playlist.playlistId))",
            body: Body(name: playlist.name, trackIds: playlist.trackIds,
                       folder: playlist.folderChain, ifUnchangedSince: ifUnchangedSince),
            cache: .useProtocolCachePolicy)

        if status == 409 {
            // Nothing was written. The response holds the stored copy, which is the reason
            // for the conditional write.
            let stored = try? RPMJSON.decoder.decode(CloudPlaylist.self, from: data)
            throw PlaylistConflict(stored: stored, name: playlist.name)
        }

        // This is a refusal and not a request to sign in again: a playlist write is turned
        // down for reasons that are about the playlist.
        if status == 400 || status == 403 || status == 402 {
            throw RPMError.refused(status: status, reason: nil)
        }

        guard (200..<300).contains(status) else {
            throw RPMError.status(status)
        }

        return (try? RPMJSON.decoder.decode(Said.self, from: data))?.updatedAt ?? 0
    }

    /// Removes a playlist from the cloud. The tracks it named are not changed: they
    /// may belong to a record that the user picked, or to another playlist.
    ///
    /// **A 404 has the same result.** Asking for something to be removed when it is
    /// already gone is not a failure.
    public func deletePlaylist(id: String) async throws {
        let (status, _) = try await transport.raw("DELETE", "cloud/playlist/\(escaped(id))",
                                                  cache: .useProtocolCachePolicy)

        guard (200..<300).contains(status) || status == 404 else {
            throw RPMError.status(status)
        }
    }

    // ── album marks ──

    /// Every record that a shelf's owner has marked, in one call. A client with two
    /// thousand albums must not make two thousand requests to find the eleven favourites.
    ///
    /// For a borrowed shelf the store returns the owner's classical marks and no
    /// favourites. A favourite is the owner's taste, and the heart on a borrowed
    /// record belongs to this account. The result is checked to be that shelf's, for the
    /// same reason as in `playlists`.
    public func albumMarks(_ shelf: CloudShelf) async throws -> [CloudAlbumMark] {
        let answer = try await transport.get(
            "cloud/album-marks" + shelf.query(first: true), as: CloudAlbumMarksResponse.self)

        if !shelf.isOwn && answer.owner != shelf.ownerId {
            throw RPMError.notServed(ownerId: shelf.ownerId)
        }
        return answer.albums
    }

    /// Reads use `cloud/album-marks` and writes use `cloud/album-mark/{key}`. The read route is
    /// plural and the write route is singular, and the key is in the path and not in the body.
    @discardableResult
    public func putAlbumMark(
        albumKey: String, favorite: Bool, favoritedUtcTicks: Int64
    ) async throws -> Int64 {
        struct Body: Encodable { let favorite: Bool; let favoritedAt: Int64 }

        return try await transport.send(
            "PUT", "cloud/album-mark/\(escaped(albumKey))",
            body: Body(favorite: favorite, favoritedAt: favorite ? favoritedUtcTicks : 0),
            as: CloudAlbumMarkStamp.self).updatedAt
    }

    // ── artwork ──

    /// The covers a shelf has, in whichever shape the store answers.
    ///
    /// **This method throws and does not return an empty list on failure.** "This collection
    /// has no covers" and "the store could not be reached" would be the same empty list. A
    /// caller that cannot tell them apart must choose between two mistakes: trust the empty
    /// answer and draw placeholders for ten minutes over a disk full of sleeves, or distrust
    /// it and ask again for every record without end. Only the caller knows which cost it
    /// can accept, so only the caller can decide.
    public func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] {
        try await transport.get("cloud/art" + shelf.query(first: true),
                                as: AlbumArtIndex.self).covers
    }

    /// Where one album's cover can be fetched from, signed.
    ///
    /// **A 404 here is the ordinary answer**, not a fault. Most records have no
    /// stored cover, and a caller should consult the index (`artCatalog`) before
    /// asking, so that a wall of records does not make one request per tile. Nil covers both
    /// cases.
    ///
    /// The shelf decides whose sleeve is asked for, and the grant is checked when the URL
    /// is signed. A share that is taken back removes the pictures in the same way as the
    /// music.
    ///
    /// `size` selects the original or one of the API's cut copies. The stamp in the result is
    /// the original's in both cases, because a copy is cut again when the original changes.
    public func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? {
        let owner = shelf.query(first: true)
        let sized = size.parameter.map { (owner.isEmpty ? "?" : "&") + $0 } ?? ""

        guard let said = try? await transport.get(
            "cloud/art/\(escaped(albumKey))" + owner + sized,
            as: AlbumArtUrlResponse.self)
        else { return nil }
        return StoredCover(albumKey: albumKey, updatedAt: said.updatedAt, url: said.url)
    }

    /// The picture itself.
    ///
    /// This is the second request, and it sends **no credential**. The URL from `art` is signed
    /// for exactly the request it describes. An Authorization header would make it a different
    /// request, which the store refuses.
    public func artwork(at url: URL) async throws -> Data {
        try await transport.unauthenticatedData(url)
    }

    /// Pictures of the artist (not of the record), best first, for the screen that shows one
    /// behind the record.
    ///
    /// **Backdrops are the only pictures that are looked up by name.** A cover
    /// guessed from an artist and a title can be the wrong pressing, the
    /// wrong region, or another record entirely, and it looks the same as a right one. So a
    /// sleeve is either the album's own art or the placeholder, and only backdrops are fetched
    /// from a catalogue. A wrong backdrop shows a photograph of the wrong band, which the user
    /// can see and correct.
    ///
    /// Empty is the ordinary answer: most artists in most libraries have no photograph
    /// anywhere. **A failure is not that answer.** It is thrown and not turned into an empty
    /// list, because the caller remembers an empty list for the session. If a failed request
    /// were remembered, the artist would stay blank for an hour.
    ///
    /// The server asks fanart.tv for these with rpm's project key. It also adds the account's
    /// own fanart.tv key when one is saved (it is set on the desktop), so the phone needs no key.
    public func artistPictures(artist: String, album: String?) async throws -> ArtistPictures {
        guard !artist.trimmingCharacters(in: .whitespaces).isEmpty else { return .none }

        var path = "artwork?artist=\(escaped(artist))"
        if let album, !album.isEmpty { path += "&album=\(escaped(album))" }

        let (said, partial) = try await transport.getMarked(path, as: ArtworkLookup.self)

        return ArtistPictures(backdrops: said.backgrounds.compactMap(URL.init(string:)),
                              squares: said.thumbs.compactMap(URL.init(string:)),
                              logo: said.logo.flatMap(URL.init(string:)),
                              partial: partial)
    }

    /// How many times the world has played each song on one record. See ``RecordPlays``.
    ///
    /// The request and its values are the same as the desktop's popularity sweep makes
    /// (`RpmMetadataApi.GetPlaysAsync`), so a record that the desktop has asked about is answered
    /// from the server's cache. Change both together.
    ///
    /// Throws when the server could not ask (it answers 503) or could not be reached. An empty
    /// answer means the catalogues were asked and do not have the record.
    ///
    /// - Parameters:
    ///   - tracks: how many songs the record has. The server picks the pressing with it.
    ///   - release: the MusicBrainz release that the record is tagged with, or nil. The caller
    ///     states it, because without it the server searches by name.
    public func recordPlays(artist: String, album: String, tracks: Int,
                            release: String?) async throws -> (plays: RecordPlays, partial: Bool) {
        guard !artist.trimmingCharacters(in: .whitespaces).isEmpty,
              !album.trimmingCharacters(in: .whitespaces).isEmpty else { return (.empty, false) }

        var path = "metadata/plays?artist=\(escaped(artist))&album=\(escaped(album))"
        if tracks > 0 { path += "&tracks=\(tracks)" }
        if let release, !release.isEmpty { path += "&release=\(escaped(release))" }

        let (plays, partial) = try await transport.getMarked(path, as: RecordPlays.self)
        return (plays, partial)
    }

    // ── the account ──

    public func quota() async throws -> CloudQuota {
        try await transport.get("cloud/quota", as: CloudQuota.self)
    }

    /// The installs this account has signed in on.
    ///
    /// The response is an envelope and not a bare array. The service answers
    /// `{"devices":[...]}`, and a client that decodes an array would report a type mismatch
    /// for a good 200 response.
    public func devices() async throws -> [CloudDevice] {
        try await transport.get("cloud/devices", as: DevicesResponse.self).devices ?? []
    }

    /// Tells the account that this install exists, so the user's other computers can
    /// recognise it without any other step. The server checks the id against
    /// the key, and a pair that does not match is refused.
    public func registerDevice(deviceId: String, publicKey: String, name: String) async throws {
        struct Body: Encodable { let deviceId: String; let publicKey: String; let name: String }
        try await transport.sendVoid("POST", "cloud/devices",
                                     body: Body(deviceId: deviceId, publicKey: publicKey, name: name))
    }

    // ── what this listener has played ──
    //
    // One row per track per device, holding that device's own total. This phone writes
    // its own rows only. A re-send must be harmless, because the server stores each
    // device's total and not a list of plays (see the server's TrackPlayStore).

    /// Every play row this listener has on any device, or only what the store has touched
    /// since a stamp this phone has already taken in.
    ///
    /// The response is an envelope and not a bare array, for the same reason as in `devices()`:
    /// the service answers `{"tracks":[...]}`, and a client that decodes an array would report
    /// a type mismatch for a good 200 response.
    public func trackPlays(since: Int64 = 0) async throws -> [CloudTrackPlays] {
        struct Said: Decodable { let tracks: [CloudTrackPlays]? }
        return try await transport.get("cloud/track-plays?since=\(since)", as: Said.self)
            .tracks ?? []
    }

    /// Sends this phone's play totals. Returns the stamp that the store wrote them under,
    /// which the phone records as agreed.
    public func sendTrackPlays(deviceId: String, rows: [TrackPlaysEntry]) async throws -> Int64 {
        struct Body: Encodable { let deviceId: String; let tracks: [TrackPlaysEntry] }
        struct Said: Decodable { let updatedAt: Int64 }
        return try await transport.send("PUT", "cloud/track-plays",
                                        body: Body(deviceId: deviceId, tracks: rows),
                                        as: Said.self).updatedAt
    }

    // ── what this listener has heard on the radio ──
    //
    // The same shape as the play counts: one row per station per device, holding that
    // device's own totals. See the server's StationListenStore.

    /// Every station row this listener has on any device, or only the rows that the store has
    /// changed since a stamp this phone has already taken in.
    public func stationListens(since: Int64 = 0) async throws -> [CloudStationListens] {
        struct Said: Decodable { let stations: [CloudStationListens]? }
        return try await transport.get("cloud/station-listens?since=\(since)", as: Said.self)
            .stations ?? []
    }

    /// Sends this phone's radio totals. Returns the stamp that the store wrote them under.
    public func sendStationListens(deviceId: String, rows: [StationListensEntry]) async throws -> Int64 {
        struct Body: Encodable { let deviceId: String; let stations: [StationListensEntry] }
        struct Said: Decodable { let updatedAt: Int64 }
        return try await transport.send("PUT", "cloud/station-listens",
                                        body: Body(deviceId: deviceId, stations: rows),
                                        as: Said.self).updatedAt
    }

    // ── the saved radio stations ──
    //
    // One row per station per account, holding the newest change from any device. See the
    // server's StationFavoriteStore and RPMRadio's FavoriteLedger.

    /// Every change to the saved stations that the store has recorded since a stamp this phone
    /// has already taken in, including removals.
    public func stationFavorites(since: Int64 = 0) async throws -> [CloudStationFavorite] {
        struct Said: Decodable { let stations: [CloudStationFavorite]? }
        return try await transport.get("cloud/station-favorites?since=\(since)", as: Said.self)
            .stations ?? []
    }

    /// The word timing measured from a track's recording (`cloud/lyric-timing/{rpmId}`), for
    /// karaoke. A track that has not been measured gives a 404, which means no lines. An answer
    /// that names a different owner than the borrowed shelf's owner throws, as every borrowed
    /// read does.
    public func lyricTiming(rpmId: String, on shelf: CloudShelf) async throws -> [MeasuredLine] {
        struct Said: Decodable { let lines: [MeasuredLine]?; let owner: String? }
        do {
            let said = try await transport.get("cloud/lyric-timing/" + escaped(rpmId) + shelf.query(first: true),
                                               as: Said.self)
            if !shelf.isOwn && said.owner != shelf.ownerId {
                throw RPMError.notServed(ownerId: shelf.ownerId)
            }
            return said.lines ?? []
        } catch RPMError.refused(status: 404, _) {
            return []
        }
    }

    /// The lyric sheet the owner chose for a track on a desktop (`cloud/lyric-sheet/{rpmId}`),
    /// as LRC text. Nil when the owner chose none, which the server says with a 404; the reader
    /// then asks LRCLIB. An answer that names a different owner than the borrowed shelf's owner
    /// throws, as every borrowed read does.
    public func lyricSheet(rpmId: String, on shelf: CloudShelf) async throws -> String? {
        struct Said: Decodable { let lrc: String?; let owner: String? }
        do {
            let said = try await transport.get("cloud/lyric-sheet/" + escaped(rpmId) + shelf.query(first: true),
                                               as: Said.self)
            if !shelf.isOwn && said.owner != shelf.ownerId {
                throw RPMError.notServed(ownerId: shelf.ownerId)
            }
            return said.lrc
        } catch RPMError.refused(status: 404, _) {
            return nil
        }
    }

    /// Asks for a track's lyrics to be timed from its recording (`.../measure`). The server
    /// answers at once and the transcoder does the work afterwards. ``lyricTiming(rpmId:on:)``
    /// reads the result later.
    public func measureLyrics(rpmId: String, on shelf: CloudShelf, lines: [SheetLine]) async throws {
        struct Body: Encodable { let lines: [SheetLine] }
        struct Said: Decodable {}
        _ = try await transport.send("POST", "cloud/lyric-timing/" + escaped(rpmId) + "/measure" + shelf.query(first: true),
                                     body: Body(lines: lines), as: Said.self)
    }

    /// Every saved station of the account that shares `shelf` with this one, with the newest
    /// change of each. It is read only: nothing writes another account's stations. An answer that
    /// names a different owner throws, as every borrowed read does, because a server that does
    /// not know `owner=` answers with the caller's own stations.
    public func stationFavorites(of shelf: CloudShelf) async throws -> [CloudStationFavorite] {
        struct Said: Decodable { let stations: [CloudStationFavorite]?; let owner: String? }
        let said = try await transport.get("cloud/station-favorites?since=0" + shelf.query(first: false),
                                           as: Said.self)
        if !shelf.isOwn && said.owner != shelf.ownerId {
            throw RPMError.notServed(ownerId: shelf.ownerId)
        }
        return said.stations ?? []
    }

    /// Sends this phone's changes to the saved stations. The store keeps each change that is
    /// newer than the one it holds. Returns the stamp that the store wrote them under.
    public func sendStationFavorites(_ rows: [StationFavoriteEntry]) async throws -> Int64 {
        struct Body: Encodable { let stations: [StationFavoriteEntry] }
        struct Said: Decodable { let updatedAt: Int64 }
        return try await transport.send("PUT", "cloud/station-favorites",
                                        body: Body(stations: rows), as: Said.self).updatedAt
    }

    public func shares() async throws -> CloudShares {
        try await transport.get("cloud/shares", as: CloudShares.self)
    }

    public func revokeShare(granteeId: String) async throws {
        try await transport.sendVoid("DELETE", "cloud/shares/\(escaped(granteeId))")
    }

    // ── plumbing ──

    /// Percent-encoding for a path or query segment.
    ///
    /// An album key is the artist and the title joined by a pipe, and a track title can
    /// hold any text a person typed. `.urlPathAllowed` would leave a slash in a
    /// name unchanged and turn one segment into two.
    private func escaped(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}

/// One row of a catalogue push. Everything but the id is optional, and the server does not
/// change what the row does not mention.
public struct CatalogPush: Encodable, Sendable {
    public let rpmId: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let relativePath: String?
    public let tags: CloudTrackTags?

    public init(rpmId: String, title: String? = nil, artist: String? = nil,
                album: String? = nil, relativePath: String? = nil,
                tags: CloudTrackTags? = nil) {
        self.rpmId = rpmId; self.title = title; self.artist = artist
        self.album = album; self.relativePath = relativePath; self.tags = tags
    }
}

extension Array {
    /// Fixed-size batches. The server caps several routes, and a request for more fails
    /// completely and does not return some of the items.
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
