import Foundation
import RPMKit

/// Which photograph an artist was left on, kept where it outlasts the app.
///
/// This is the remembered half of a port of `RPM.Mobile/Services/BackdropChooser.cs`.
///
/// The score decides which of an artist's photographs leads, and it is right most of the time.
/// When it is not, the person looking at the screen says so with a swipe. That swipe is a choice,
/// not a passing mood. It has to survive the next track, the next album and the next run. Otherwise
/// the score would undo it every time the record changes.
///
/// The score's own winner is written here too. That is what makes the judging cost once per artist,
/// not once per record.
///
/// These picks are kept in **documents**, unlike the pictures, which are kept in caches. The system
/// may reclaim a cache, and a cover it reclaims is fetched again without the user noticing. A pick is
/// a decision the user made. If the system reclaimed it, the decision would be lost.
struct BackdropPicks {
    private let file: URL
    private var known: [String: String]

    /// The usual home.
    static func inDocuments(named name: String = "backdrops.json") -> BackdropPicks {
        // tvOS has no documents folder that an app may write to, so the picks go in `KeptFiles.folder` there.
        #if os(tvOS)
        let root = KeptFiles.folder
        #else
        let root = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        #endif

        return BackdropPicks(file: root.appendingPathComponent(name))
    }

    init(file: URL) {
        self.file = file

        // Read once. The file is a few lines. A file that fails to parse was never written properly. Starting
        // again from nothing loses only this preference. Failing would also lose the artwork.
        known = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// The photograph this artist was left on, or nil if no photograph has been chosen for them.
    func pick(_ artist: String) -> URL? {
        known[key(artist)].flatMap(URL.init(string:))
    }

    /// Records where the artist was left. The write happens at once. A decision held in memory until later
    /// would be lost if the app were force-quit.
    mutating func remember(_ url: URL, for artist: String) {
        guard known[key(artist)] != url.absoluteString else { return }

        known[key(artist)] = url.absoluteString
        try? JSONEncoder().encode(known).write(to: file, options: .atomic)
    }

    /// Clears everything. Used on sign-out, and on sign-in as a different user.
    mutating func forget() {
        known = [:]
        try? FileManager.default.removeItem(at: file)
    }

    /// Lowercased, so the same artist spelled two ways across two tracks is one artist.
    private func key(_ artist: String) -> String { artist.lowercased() }
}
