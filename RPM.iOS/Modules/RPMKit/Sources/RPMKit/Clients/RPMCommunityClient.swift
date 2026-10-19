import Foundation

/// RPM's shared album wall: the album entries that everybody shares, and what people wrote about them.
///
/// **Reading does not need a token. Writing does.** Every read works while signed out, so an album page can
/// show its reviews to someone who has never made an account. The writes are the calls that fail when no
/// token is given.
///
/// The routes are not under a `community/` prefix. They sit at the root of the same host as the cloud routes,
/// for example `albums/resolve` and `profile`.
public struct RPMCommunityClient: Sendable {
    private let transport: Transport

    public init(transport: Transport) { self.transport = transport }

    // Albums

    /// The album's RPM id. RPM creates the id if it has not seen this record before.
    ///
    /// Every id sent here is also stored as an alias. So a copy linked to one catalogue and a copy linked to
    /// another end up on the same page. Sending the ids that are already known costs nothing, and it is what
    /// joins the two.
    public func resolveAlbum(
        artist: String?, title: String, year: Int = 0, catno: String? = nil,
        discogsReleaseId: String? = nil, trackCount: Int = 0,
        musicBrainzReleaseId: String? = nil, musicBrainzReleaseGroupId: String? = nil,
        barcode: String? = nil, discId: String? = nil
    ) async throws -> RPMAlbum {
        struct Body: Encodable {
            let artist: String?; let title: String; let year: Int
            let catno: String?; let discogsReleaseId: String?; let trackCount: Int
            let musicBrainzReleaseId: String?; let musicBrainzReleaseGroupId: String?
            let barcode: String?; let discId: String?
        }
        return try await transport.send("POST", "albums/resolve", body: Body(
            artist: artist, title: title, year: year, catno: catno,
            discogsReleaseId: discogsReleaseId, trackCount: trackCount,
            musicBrainzReleaseId: musicBrainzReleaseId,
            musicBrainzReleaseGroupId: musicBrainzReleaseGroupId,
            barcode: barcode, discId: discId), as: RPMAlbum.self)
    }

    /// Links this album to a pressing, and returns the entry that the pressing belongs to. The answer may be an
    /// album the user has never seen. Linking to a pressing that someone else already linked joins their page.
    /// That is the purpose of the call.
    public func linkAlbum(
        artist: String?, title: String, year: Int = 0, catno: String? = nil,
        discogsReleaseId: String? = nil, musicBrainzReleaseId: String? = nil,
        musicBrainzReleaseGroupId: String? = nil, barcode: String? = nil,
        discId: String? = nil
    ) async throws -> RPMAlbum {
        struct Body: Encodable {
            let artist: String?; let title: String; let year: Int
            let catno: String?; let discogsReleaseId: String?
            let musicBrainzReleaseId: String?; let musicBrainzReleaseGroupId: String?
            let barcode: String?; let discId: String?
        }
        return try await transport.send("POST", "albums/link", body: Body(
            artist: artist, title: title, year: year, catno: catno,
            discogsReleaseId: discogsReleaseId,
            musicBrainzReleaseId: musicBrainzReleaseId,
            musicBrainzReleaseGroupId: musicBrainzReleaseGroupId,
            barcode: barcode, discId: discId), as: RPMAlbum.self)
    }

    /// The same match as `resolveAlbum`, but without creating an entry.
    ///
    /// Returns nil when nobody has written about this record. That is the usual answer, and it is not an error.
    /// The service says so with a 404. If this call threw, every album page in a new library would show an error.
    public func lookupAlbum(
        artist: String?, title: String, year: Int = 0, catno: String? = nil
    ) async -> RPMAlbum? {
        var path = "albums/lookup?title=" + escaped(title)
        if let artist, !artist.isEmpty { path += "&artist=" + escaped(artist) }
        if year > 0 { path += "&year=\(year)" }
        if let catno, !catno.isEmpty { path += "&catno=" + escaped(catno) }

        return try? await transport.get(path, as: RPMAlbum.self)
    }

    public func album(id albumId: String) async -> RPMAlbum? {
        try? await transport.get("albums/\(escaped(albumId))", as: RPMAlbum.self)
    }

    /// Every catalogue id that this album answers to.
    public func aliases(albumId: String) async throws -> [RPMAlbumAlias] {
        (try? await transport.get(
            "albums/\(escaped(albumId))/aliases", as: [RPMAlbumAlias].self)) ?? []
    }

    public func searchAlbums(_ query: String, limit: Int = 20) async throws -> [RPMAlbum] {
        try await transport.get(
            "albums/search?q=\(escaped(query))&limit=\(limit)", as: [RPMAlbum].self)
    }

    // Reviews

    /// - Parameter group: When true, returns what people wrote about every pressing of this album, not only
    ///   this one.
    public func reviews(
        albumId: String, sort: RPMReviewSort = .votes,
        page: Int = 1, pageSize: Int = 20, group: Bool = false
    ) async throws -> RPMReviewPage {
        let path = "albums/\(escaped(albumId))/reviews"
            + "?sort=\(sort.rawValue)&page=\(page)&pageSize=\(pageSize)"
            + (group ? "&group=true" : "")
        return try await transport.get(path, as: RPMReviewPage.self)
    }

    public func myReview(albumId: String) async -> RPMReview? {
        try? await transport.get("albums/\(escaped(albumId))/reviews/me", as: RPMReview.self)
    }

    /// - Parameter rating: Half-stars, doubled, so 1 to 10.
    @discardableResult
    public func writeReview(albumId: String, rating: Int, body: String) async throws -> RPMReview {
        struct Body: Encodable { let rating: Int; let body: String }
        return try await transport.send(
            "PUT", "albums/\(escaped(albumId))/reviews/me",
            body: Body(rating: rating, body: body), as: RPMReview.self)
    }

    public func deleteMyReview(albumId: String) async throws {
        try await transport.sendVoid("DELETE", "albums/\(escaped(albumId))/reviews/me")
    }

    /// - Parameter value: 1 to vote it up, -1 to vote it down, 0 to withdraw the vote.
    @discardableResult
    public func vote(albumId: String, userId: String, value: Int) async throws -> RPMReview? {
        struct Body: Encodable { let value: Int }
        return try? await transport.send(
            "POST", "albums/\(escaped(albumId))/reviews/\(escaped(userId))/vote",
            body: Body(value: value), as: RPMReview.self)
    }

    // Comments

    public func comments(albumId: String) async throws -> [RPMComment] {
        (try? await transport.get(
            "albums/\(escaped(albumId))/comments", as: [RPMComment].self)) ?? []
    }

    @discardableResult
    public func addComment(albumId: String, body: String) async throws -> RPMComment {
        struct Body: Encodable { let body: String }
        return try await transport.send(
            "POST", "albums/\(escaped(albumId))/comments",
            body: Body(body: body), as: RPMComment.self)
    }

    public func deleteComment(albumId: String, commentId: String) async throws {
        try await transport.sendVoid(
            "DELETE", "albums/\(escaped(albumId))/comments/\(escaped(commentId))")
    }

    // Profiles

    public func profile() async throws -> RPMProfile {
        try await transport.get("profile", as: RPMProfile.self)
    }

    /// Another person's name and picture, by their id.
    ///
    /// **The route is `profiles`, in plural.** The caller's own profile is at `profile`. Everyone else's is at
    /// `profiles/{id}`.
    ///
    /// Nil is a valid answer. An id that never made a profile belongs to someone with nothing to show, so the
    /// caller has to use some other name for them. A failure throws. That lets a caller tell an outage from a
    /// person with no name, and ask again later, instead of keeping one bad response for the rest of the launch.
    public func publicProfile(userId: String) async throws -> RPMProfile? {
        guard !userId.isEmpty else { return nil }

        do {
            return try await transport.get("profiles/\(escaped(userId))", as: RPMProfile.self)
        } catch RPMError.refused(status: 404, _) {
            return nil
        }
    }

    /// The address where somebody's picture is drawn from, as an absolute URL.
    ///
    /// **The stamp goes in the URL, not in a header.** A changed picture then has a different address, so a
    /// cache that is already filled never has to be emptied. This is the one value on this client that a view
    /// fetches itself, instead of through `Transport`. That is why it returns an address and not bytes.
    ///
    /// It takes the profile, not the id, because only the profile says whether there is a picture.
    public func avatar(for profile: RPMProfile) -> URL? {
        guard profile.hasAvatar, !profile.userId.isEmpty else { return nil }

        var path = "profiles/\(escaped(profile.userId))/avatar"
        if profile.avatarUpdatedAt > 0 { path += "?v=\(profile.avatarUpdatedAt)" }

        return URL(string: path, relativeTo: transport.base)?.absoluteURL
    }

    @discardableResult
    public func setDisplayName(_ displayName: String) async throws -> RPMProfile {
        struct Body: Encodable { let displayName: String }
        return try await transport.send(
            "PUT", "profile", body: Body(displayName: displayName), as: RPMProfile.self)
    }

    public func report(albumId: String, kind: String, targetId: String?, reason: String) async throws {
        struct Body: Encodable {
            let albumId: String; let kind: String; let targetId: String?; let reason: String
        }
        try await transport.sendVoid("POST", "reports", body: Body(
            albumId: albumId, kind: kind, targetId: targetId, reason: reason))
    }

    // Helpers

    private func escaped(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
