import Foundation
import CryptoKit
import RPMKit

/// The Wikipedia text about records and artists, kept in memory and on disk.
///
/// The iOS version of the desktop's `TrackInfoService` cache, with the same two clocks: an
/// article is kept for 30 days, and "there is no article" for 5, so a record that gets written up
/// next week is found next week. A request that failed is not kept at all: offline is a condition
/// of the moment, and writing it down would blank the page after the network came back. Nor is an
/// answer the API marked as partial, because the API is still completing it.
///
/// **Two reads, for the two moments a page needs one.** ``cached(_:)`` answers on the frame the
/// page is built, from memory or a small file, and never asks the network, so a page opened before
/// shows its text straight away instead of pushing the songs down a moment later. ``article(_:)``
/// answers from the same caches and goes to the network only where they miss.
///
/// Main actor, because both reads are made from views and the first one must not wait. The network
/// half runs off it, in ``PapersClient``.
@MainActor
public final class ArticleStore {
    /// What a page asks about.
    public enum Subject: Sendable, Equatable {
        /// A record, as the album page names it: the album artist and title as the files spell
        /// them, and how many songs it has.
        case album(artist: String, title: String, tracks: Int)
        /// An act, under their name alone, as the artist page names them.
        case artist(String)
        /// A genre shelf, as the app spells it. Its article is the English one the desktop's table
        /// names (``GenreArticles``), whatever the languages.
        case genre(String)

        /// Which article this is about. The track count is not part of it: it helps the server
        /// tell an album from a single, and it is a property of the record the rest already
        /// names. A page uses this to check that the text it holds is about what it now shows.
        public var id: String {
            switch self {
            case let .album(artist, title, _): "album\u{1}" + Self.norm(artist) + "\u{1}" + Self.norm(title)
            case let .artist(name): "artist\u{1}" + Self.norm(name)
            case let .genre(name): "genre\u{1}" + Self.norm(name)
            }
        }

        private static func norm(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    /// An article, or the answer that there is none. Written to disk as it is.
    private struct Kept: Codable {
        let article: EncyclopediaArticle?
    }

    /// Raise when the route changes in a way that would give a subject a better answer than the
    /// one already on disk. The old files are never read again; they are in the caches folder,
    /// which the system empties when it needs the space.
    private static let version = "v1"

    private static let found: TimeInterval = 30 * 24 * 3600
    private static let blank: TimeInterval = 5 * 24 * 3600

    private let fetch: @Sendable (Subject, [String]) async throws -> ArticleAnswer
    private let languages: [String]
    private let directory: URL?

    private var memory: [String: Kept] = [:]

    /// Keys whose file was looked for this session and was not there. Pages are rebuilt every
    /// time the screen above them changes, and each rebuild asks ``cached(_:)`` again; without
    /// this, every one of those would be a trip to the disk for a file that is not there.
    private var notOnDisk: Set<String> = []

    /// In flight, keyed like the caches, so two pages asking about one record make one request.
    private var running: [String: Task<ArticleAnswer, any Error>] = [:]

    /// - Parameter languages: which Wikipedias to read, best first. Part of every key, so a
    ///   different language is a different answer. See ``Encyclopedia/languages(preferred:)``.
    /// - Parameter directory: where the answers are written, or nil to keep them in memory only.
    public convenience init(client: PapersClient, languages: [String], directory: URL?) {
        self.init(languages: languages, directory: directory) { subject, languages in
            switch subject {
            case let .album(artist, title, tracks):
                try await client.albumArticle(artist: artist, album: title, tracks: tracks,
                                              languages: languages)
            case let .artist(name):
                try await client.artistArticle(artist: name, languages: languages)
            case let .genre(name):
                try await client.genreArticle(name)
            }
        }
    }

    init(languages: [String], directory: URL?,
         fetch: @escaping @Sendable (Subject, [String]) async throws -> ArticleAnswer) {
        self.fetch = fetch
        self.languages = languages
        self.directory = directory

        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// The usual home: under the caches. Everything in it can be asked for again.
    public static func inCaches(named folder: String = "papers") -> URL {
        let root = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent(folder, isDirectory: true)
    }

    // ── the two reads ──

    /// The article if it is already known, without asking anybody. Nil both when there is no
    /// article and when nobody has asked yet.
    public func cached(_ subject: Subject) -> EncyclopediaArticle? {
        guard let key = key(subject) else { return nil }
        return known(key)?.article
    }

    /// The article, from the caches where they have an answer and from the network where not.
    ///
    /// Nil when there is no article, and nil when the request failed. A caller that stops waiting
    /// does not stop the request: it finishes and is kept, so the page is ready next time.
    public func article(_ subject: Subject) async -> EncyclopediaArticle? {
        guard let key = key(subject) else { return nil }

        if let kept = known(key) { return kept.article }
        if let joined = running[key] { return (try? await joined.value)?.article }

        let fetch = self.fetch
        let languages = self.languages
        let asking = Task { try await fetch(subject, languages) }
        running[key] = asking
        defer { running[key] = nil }

        do {
            let answer = try await asking.value

            // Part of an answer is shown and kept nowhere, not even in memory: the API is finishing it,
            // and the next time the page opens it is asked again and served the rest.
            if !answer.partial {
                keep(key, Kept(article: answer.article))
            }
            return answer.article
        } catch {
            return nil
        }
    }

    // ── keys ──

    /// Nil for a subject that is not asked about at all: a blank name, and the compilations shelf,
    /// which is not a person (the desktop's `NobodyInParticular`).
    private func key(_ subject: Subject) -> String? {
        switch subject {
        case let .album(artist, title, _):
            if blank(artist) || blank(title) { return nil }
        case let .artist(name):
            if blank(name) || ArtistCredit.isVariousArtists(name) { return nil }
        case let .genre(name):
            if blank(name) { return nil }
        }
        return Self.version + "\u{1}" + languages.joined(separator: ",") + "\u{1}" + subject.id
    }

    private func blank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // ── memory and disk ──

    private func known(_ key: String) -> Kept? {
        if let hit = memory[key] { return hit }
        guard !notOnDisk.contains(key) else { return nil }

        guard let read = readDisk(key) else {
            notOnDisk.insert(key)
            return nil
        }
        memory[key] = read
        return read
    }

    private func keep(_ key: String, _ kept: Kept) {
        memory[key] = kept
        notOnDisk.remove(key)
        writeDisk(key, kept)
    }

    private func path(_ key: String) -> URL? {
        guard let directory else { return nil }
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(String(hash.prefix(32)) + ".json")
    }

    private func readDisk(_ key: String) -> Kept? {
        guard let file = path(key),
              let written = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              let data = try? Data(contentsOf: file),
              let kept = try? JSONDecoder().decode(Kept.self, from: data)
        else { return nil }

        let age = Date().timeIntervalSince(written)
        return age <= (kept.article == nil ? Self.blank : Self.found) ? kept : nil
    }

    private func writeDisk(_ key: String, _ kept: Kept) {
        guard let file = path(key), let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
