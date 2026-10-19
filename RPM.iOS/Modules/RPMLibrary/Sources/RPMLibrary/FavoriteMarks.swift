import Foundation
import Observation
import RPMKit

/// Which songs the listener has marked as a favourite, and the one place where anything
/// asks.
///
/// The mark is a field on a catalogue row. A
/// `CloudTrack` is a value, though. The copy a screen holds is taken when the catalogue it
/// came from is read. A queue built when an album was opened keeps the marks as they were
/// at that time. Marking a song on one screen does not change the copies already handed
/// out, so other screens would still draw an empty heart for a song that was loved.
///
/// So the mark is kept apart from the track and is asked for by id. This type is the only
/// place that answers that question, and the answer is current whenever it is asked.
///
/// **`@Observable` and `@MainActor`, with no lock and no change event.** A heart is a
/// view of this type. SwiftUI redraws a view when the state it read changes, so no
/// separate observer callback is needed. The type is main-actor because it is view state.
/// Background reads hop to the main actor with one `await`, in a listing that already
/// has several.
@MainActor
@Observable
public final class FavoriteMarks {
    /// The marked songs of the catalogue in hand, and the stamp each one carries.
    /// Only the marked ones are kept: an unmarked song is an absence, which is what the
    /// catalogue says about the other songs. Replaced whole, never edited.
    private var catalog: [String: Int64] = [:]

    /// The marks and unmarks made on this device since that catalogue was read, and when
    /// each was made. An entry is kept only until a catalogue comes back that agrees with it.
    ///
    /// **Two layers. This one is what makes the answer independent of arrival order.** A
    /// mark is sent to the server first, and a catalogue that contains it may arrive later.
    /// A read of the whole catalogue is often already in flight, though, and it answers with
    /// a listing that was true before the tap. So a mark made here is held over whatever
    /// catalogue arrives. It is dropped only once a catalogue comes back that says the same
    /// thing. Whichever order the push and the read land in, the listener's own last word
    /// stands.
    private var mine: [String: Mark] = [:]

    public struct Mark: Equatable, Sendable {
        public let on: Bool
        public let at: Int64
        public init(on: Bool, at: Int64) { self.on = on; self.at = at }
    }

    public init() {}

    /// Reads the marks off a catalogue that has just arrived.
    ///
    /// What this device has said since then stands over the catalogue, unless the catalogue
    /// agrees. A listing read before a tap cannot be allowed to undo the tap. A listing
    /// that has caught up leaves this device with nothing more to say. A mark that the
    /// catalogue disagrees with is not resolved either way, because the push that made it
    /// may not be in this listing yet.
    public func read(_ tracks: [CloudTrack]) {
        var fresh: [String: Int64] = [:]
        for track in tracks where track.tags?.favorite == true && !track.rpmId.isEmpty {
            fresh[track.rpmId] = track.tags?.favoritedAt ?? 0
        }

        catalog = fresh

        // Dropped only where the catalogue now agrees with what this device said.
        for (id, mark) in mine where (fresh[id] != nil) == mark.on {
            mine[id] = nil
        }
    }

    /// Marks a song, or clears the mark. This is the listener's own word, and it takes
    /// priority over the catalogue until a catalogue arrives that says the same thing.
    ///
    /// - Parameter at: when the song was marked, which sets the order of the favourites
    ///   list. Zero when the mark is cleared, because an unmarked song is in no list to be
    ///   ordered in.
    public func note(_ rpmId: String, favorite: Bool, at: Int64) {
        guard !rpmId.isEmpty else { return }
        mine[rpmId] = Mark(on: favorite, at: favorite ? at : 0)
    }

    /// Whether this song is marked as a favourite. This is the question every heart asks.
    public func isMarked(_ rpmId: String) -> Bool {
        guard !rpmId.isEmpty else { return false }
        if let ours = mine[rpmId] { return ours.on }
        return catalog[rpmId] != nil
    }

    /// The mark and its stamp together. A caller must put these back when a push it made
    /// is refused.
    ///
    /// The value is read BEFORE the push, not worked out after it. "The other state" is
    /// not always the state that was there. A song marked twice from two screens would
    /// otherwise be put back into a state it was never in.
    public func markOf(_ rpmId: String) -> Mark {
        guard !rpmId.isEmpty else { return Mark(on: false, at: 0) }
        if let ours = mine[rpmId] { return ours }
        if let at = catalog[rpmId] { return Mark(on: true, at: at) }
        return Mark(on: false, at: 0)
    }

    /// When this song was marked. Used for the order of the generated list, newest first.
    /// This device's own stamp is used where it has one. A song marked a moment ago belongs
    /// at the top of that list, not at the bottom under a catalogue that has not been read
    /// since.
    public func markedAt(_ rpmId: String) -> Int64 { markOf(rpmId).at }

    /// Every marked song in a library, **newest mark first**.
    ///
    /// This is a question asked of the rows, not a list that anybody keeps. That is why
    /// the playlists tab calls this list generated: there is nothing in the cloud to open,
    /// and the only order is the one the marks themselves give.
    ///
    /// This covers the user's own library, whatever is on screen. A favourite is a tag on
    /// a catalogue row under the account that holds the file. A borrowed shelf carries none
    /// of them, and it never can.
    public func marked(in albums: [CloudAlbum]) -> [CloudTrack] {
        albums
            .flatMap(\.tracks)
            .filter { isMarked($0.rpmId) }
            .sorted {
                let mine = markedAt($0.rpmId), theirs = markedAt($1.rpmId)
                guard mine == theirs else { return mine > theirs }

                // Same instant. For marks read off one listing, that is most of them.
                // Sort those by name, so the list does not change its order between
                // launches.
                return ($0.title ?? "").compare($1.title ?? "", options: .caseInsensitive,
                                                range: nil, locale: .current) == .orderedAscending
            }
    }

    /// Clears every mark. Used when signing out. The marks belong to the library they were
    /// made in, and the next listener to use this phone must not see which songs the last
    /// one loved.
    public func forget() {
        catalog = [:]
        mine = [:]
    }
}
