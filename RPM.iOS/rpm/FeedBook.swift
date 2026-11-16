import Foundation
import Observation
import RPMKit
import RPMUI
import RPMLibrary

/// Everyone's posts and album reviews, newest first: the Feed tab. It is the Android app's `FeedBook`.
///
/// While the server has no feed (404, or the 401 it answers for a route it does not have), a test build shows the
/// sample's posts and reviews, with the reader's own sample posts among them (``RPMProfileSample/everyone``).
@MainActor
@Observable
final class FeedBook {
    /// The reader's name, id, photo and supporter's mark, as their sample posts carry them.
    struct Me {
        let name: String
        let userId: String
        let hasAvatar: Bool
        let supporter: Bool
    }

    private let community: RPMCommunityClient
    private let sample: (() -> RPMProfileSample?)?

    /// The reader as their own page shows them, for their sample posts: read before the sample is built.
    private let me: @MainActor () async -> Me?

    init(community: RPMCommunityClient, sample: (() -> RPMProfileSample?)?, me: @escaping @MainActor () async -> Me?) {
        self.community = community
        self.sample = sample
        self.me = me
    }

    private(set) var items: [RPMFeedItem] = []
    private(set) var next: Int64?
    private(set) var answered = false
    private(set) var trouble: String?
    private(set) var isSample = false

    private var newest = 0
    private var readingMore = false

    func read() async {
        newest += 1
        let ticket = newest
        do {
            let page = try await community.everyone()
            guard ticket == newest else { return }
            isSample = false
            items = page.items
            next = page.next
            answered = true
            trouble = nil
        } catch let missing where PersonPage.isMissingRoute(missing) {
            guard ticket == newest else { return }
            guard let shown = sample?() else {
                trouble = Loc.get("Rpm_Profile_Offline")
                return
            }
            isSample = true
            let reader = await me()
            let own: [RPMFeedItem] = shown.feed.items.compactMap { item in
                guard case .post(let post) = item else { return nil }
                return .post(post.by(ownerId: reader?.userId ?? "", name: reader?.name ?? "",
                                     hasAvatar: reader?.hasAvatar == true, supporter: reader?.supporter == true))
            }
            items = (shown.everyone + own).sorted { $0.createdAt > $1.createdAt }
            next = nil
            answered = true
            trouble = nil
        } catch {
            guard ticket == newest else { return }
            trouble = (error as? RPMError)?.userMessage(refused: Loc.get("Rpm_Profile_Offline")) ?? Loc.get("Rpm_Profile_Offline")
        }
    }

    /// Reads the next page. A page that comes back empty while more follow (everything on it was by someone blocked)
    /// is passed over, so the list never stops on it.
    func more() async {
        guard !readingMore else { return }
        readingMore = true
        defer { readingMore = false }
        let ticket = newest
        while let before = next {
            guard let page = try? await community.everyone(before: before), ticket == newest else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            next = page.next
            if !page.items.isEmpty { return }
        }
    }

    /// Votes on a post. On the sample feed it counts here only, so the keys can be tried.
    func vote(_ post: RPMPost, _ value: Int) async {
        let changed: RPMPost
        if isSample {
            changed = post.voted(value)
        } else {
            guard let said = try? await community.vote(on: post, value: value) else { return }
            changed = said
        }
        replace(.post(changed))
    }

    /// Votes on a review. On the sample feed nothing is sent, as the server has no such review.
    func voteReview(_ shown: RPMFeedReview, _ value: Int) async {
        guard !isSample,
              let changed = try? await community.vote(albumId: shown.review.albumId, userId: shown.review.userId, value: value)
        else { return }
        replace(.review(RPMFeedReview(review: changed, albumArtist: shown.albumArtist,
                                      albumTitle: shown.albumTitle, albumYear: shown.albumYear)))
    }

    private func replace(_ item: RPMFeedItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    }
}

extension AppModel {
    /// The reader's own copy of a reviewed album, matched by artist and title; nil when it is not in their collection.
    func album(for shown: RPMFeedReview) -> CloudAlbum? {
        let artist = Self.plain(shown.albumArtist)
        let title = Self.plain(shown.albumTitle)
        guard !title.isEmpty else { return nil }
        return albums.first { Self.plain($0.album) == title && Self.plain($0.artist) == artist }
    }

    private static func plain(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
