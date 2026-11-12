import Foundation
import Observation
import RPMKit

/// What listeners wrote on one artist's wall, and what the reader is typing there.
///
/// This is the state behind the wall at the foot of the artist page. It is held by the root view
/// for each artist, for the reason given on ``ReviewWall``.
///
/// **Reading never creates the artist's entry.** RPM has no entry for most artists, and reading
/// their wall must not make one. The entry is created by the first post (see ``post()``).
///
/// **The newest read wins, not the last one to answer.** The wall is read when the page opens, and
/// again after every post and delete. These reads can overlap: a post can be sent while the first
/// read is still on its way. Each read takes a number, and its answer is used only while no newer
/// read has started. A read starts after its own write has finished, so the newest read always
/// sees every write that came before it.
@MainActor
@Observable
final class ArtistPosts {
    private let community: RPMCommunityClient

    /// The artist as the collection names them, which is also the name RPM keeps them under.
    let name: String

    init(community: RPMCommunityClient, name: String) {
        self.community = community
        self.name = name
    }

    /// RPM's entry for the artist. Nil while the wall is being read, and after a read that found
    /// nobody has written about them.
    private(set) var entry: RPMArtist?
    private(set) var lines: [RPMWallEntry] = []

    /// Whether the wall has been read. False while it is being read and after a failed read, so a
    /// wall that could not be read is not shown as an empty one.
    private(set) var answered = false

    /// Why the wall could not be read or written, or nil.
    private(set) var trouble: String?

    /// Whether a post is on its way.
    private(set) var sending = false

    /// What is typed in the box. It is kept here and not in the page, so it survives the page being
    /// built again.
    var draft = ""

    /// The number of the newest read. See the type's notes.
    private var newest = 0

    // ── reading ──

    /// Reads the wall: the artist's entry by name, then its lines. An artist with no entry has a
    /// wall with nothing on it.
    func read() async {
        newest += 1
        let ticket = newest

        do {
            var found = entry
            if found == nil { found = try await community.lookupArtist(name: name) }

            var said: [RPMWallEntry] = []
            if let found { said = try await community.wall(artistId: found.artistId) }

            guard ticket == newest else { return }
            if let found { entry = found }
            lines = said
            answered = true
            trouble = nil
        } catch {
            guard ticket == newest else { return }
            trouble = message(error)
        }
    }

    // ── writing ──

    /// Sends what is in the box. The artist's entry is created here when it does not exist yet:
    /// the first person to write about an artist makes the entry.
    ///
    /// The wall is read again afterwards rather than the new line added to the list. Other people
    /// may have written while this was typed, and the list should show what the server holds.
    func post() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }

        sending = true
        defer { sending = false }

        do {
            let artist: RPMArtist
            if let entry {
                artist = entry
            } else {
                artist = try await community.resolveArtist(name: name)
            }
            entry = artist

            try await community.postToWall(artistId: artist.artistId, body: body)

            // Only the text that was sent is removed. Anything typed while it was on its way stays.
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == body { draft = "" }
        } catch {
            trouble = message(error)
            return
        }

        await read()
    }

    /// Removes the reader's own post.
    func delete(_ line: RPMWallEntry) async {
        guard let entry else { return }

        do {
            try await community.deleteWallEntry(artistId: entry.artistId, entryId: line.entryId)
        } catch {
            trouble = message(error)
            return
        }

        await read()
    }

    /// Reports somebody else's line. Returns why it failed, or nil when it was sent.
    func report(_ line: RPMWallEntry, note: String) async -> String? {
        guard let entry else { return Loc.get("Artists_WallOffline") }

        do {
            try await community.report(.wallPost(artistId: entry.artistId, entryId: line.entryId),
                                       reason: "wallpost", note: note.isEmpty ? nil : note)
            return nil
        } catch {
            return message(error)
        }
    }

    private func message(_ error: any Error) -> String {
        (error as? RPMError)?.userMessage(refused: Loc.get("Artists_WallOffline"))
            ?? Loc.get("Artists_WallOffline")
    }
}
