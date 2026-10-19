import Foundation
import Observation
import RPMKit
import RPMLibrary

/// The reviews and ratings from other listeners for one record.
///
/// This is the state behind the footer of the album page. It is kept for the open record
/// only and dropped when another record is opened.
///
/// **The album's community id is not made from the album's tags.** RPM creates an id for a
/// record the first time anybody asks about it, and every copy of the same pressing
/// resolves to the same id. So the id must be requested from the server, not built locally.
@MainActor
@Observable
final class ReviewWall {
    private let community: RPMCommunityClient
    private let album: CloudAlbum

    init(community: RPMCommunityClient, album: CloudAlbum) {
        self.community = community
        self.album = album
    }

    private(set) var entry: RPMAlbum?
    private(set) var reviews: [RPMReview] = []
    private(set) var mine: RPMReview?
    private(set) var total = 0
    private(set) var reading = false

    /// A short message for the reader when the wall could not be loaded, shown instead of
    /// an empty wall. It never mentions signing in: the app requires sign-in, so anyone
    /// on an album page is already signed in.
    private(set) var trouble: String?

    var sort: RPMReviewSort = .votes

    private var page = 1

    /// Whether there is another page to fetch.
    var hasMore: Bool { reviews.count < total }

    /// The average of all ratings, in stars (half stars are shown).
    var average: Double { (entry?.averageRating ?? 0) }
    var ratingCount: Int { entry?.ratingCount ?? 0 }

    /// The reader's own rating, in stars.
    var myStars: Double { Double(mine?.rating ?? 0) / 2 }

    // ── reading ──

    func read() async {
        guard entry == nil, !reading else { return }
        reading = true
        defer { reading = false }

        do {
            // The local tags are sent so that a record another listener already asked about
            // resolves to the same entry, not to a second one.
            entry = try await community.resolveAlbum(
                artist: album.artist, title: album.album,
                year: AlbumSort.yearOf(album.tracks),
                trackCount: album.tracks.count)

            await load(page: 1, replacing: true)
        } catch let error as RPMError {
            trouble = error.userMessage(refused: Loc.get("Album_CommunityOffline"))
        } catch {
            trouble = Loc.get("Album_CommunityOffline")
        }
    }

    func sorted(by order: RPMReviewSort) async {
        guard order != sort else { return }
        sort = order
        await load(page: 1, replacing: true)
    }

    func more() async {
        guard hasMore, !reading else { return }
        await load(page: page + 1, replacing: false)
    }

    private func load(page wanted: Int, replacing: Bool) async {
        guard let entry else { return }

        reading = true
        defer { reading = false }

        do {
            let said = try await community.reviews(albumId: entry.albumId, sort: sort,
                                                   page: wanted, pageSize: 20)

            page = wanted
            total = said.total
            reviews = replacing ? said.items : reviews + said.items
            trouble = nil

            // Requested after the page, not at the same time: most readers have not written
            // a review, so a parallel request would usually be wasted.
            if replacing { mine = await community.myReview(albumId: entry.albumId) }
        } catch let error as RPMError {
            trouble = error.userMessage(refused: Loc.get("Album_CommunityOffline"))
        } catch {
            trouble = Loc.get("Album_CommunityOffline")
        }
    }

    // ── writing ──

    /// Writes or replaces the reader's own review.
    ///
    /// - Parameter stars: 0 to 5 in steps of one half. The server API takes the value doubled.
    /// - Returns: A message when it failed, `nil` when it is done.
    func write(stars: Double, body: String) async -> String? {
        guard let entry else { return Loc.get("Album_CommunityOffline") }
        guard stars > 0 else { return Loc.get("Rpm_Album_RatingNeeded") }

        do {
            mine = try await community.writeReview(
                albumId: entry.albumId, rating: Int((stars * 2).rounded()),
                body: body.trimmingCharacters(in: .whitespacesAndNewlines))

            // The wall and the average have both changed. Load them again instead of
            // patching: the average is calculated by the server over all ratings, and a
            // local guess could disagree with it.
            await refresh()
            return nil
        } catch let error as RPMError {
            return error.userMessage(refused: Loc.get("Rpm_Album_ReviewSaveFailed"))
        } catch {
            return Loc.get("Rpm_Album_ReviewSaveFailed")
        }
    }

    func deleteMine() async -> String? {
        guard let entry else { return nil }

        do {
            try await community.deleteMyReview(albumId: entry.albumId)
            mine = nil
            await refresh()
            return nil
        } catch let error as RPMError {
            return error.userMessage(refused: Loc.get("Rpm_Album_ReviewRemoveFailed"))
        } catch {
            return Loc.get("Rpm_Album_ReviewRemoveFailed")
        }
    }

    /// Votes on another listener's review, or withdraws a vote.
    ///
    /// **A reader cannot vote on their own review.** The row does not offer it, and this
    /// guard stops any call that gets past the row.
    func vote(_ review: RPMReview, _ value: Int) async {
        guard let entry, review.userId != mine?.userId else { return }

        // Voting the same way again withdraws the vote (sends 0), because repeating
        // the same vote would change nothing.
        let wanted = review.myVote == value ? 0 : value

        guard let said = try? await community.vote(albumId: entry.albumId,
                                                   userId: review.userId, value: wanted)
        else { return }

        guard let at = reviews.firstIndex(where: { $0.userId == review.userId }) else { return }
        reviews[at] = said
    }

    private func refresh() async {
        guard let entry else { return }

        // The entry holds the average and the count, and both have changed.
        self.entry = await community.album(id: entry.albumId) ?? entry
        await load(page: 1, replacing: true)
    }
}
