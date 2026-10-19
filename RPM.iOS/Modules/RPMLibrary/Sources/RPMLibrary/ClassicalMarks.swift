import Foundation
import Observation
import RPMKit

/// Which records each shelf's owner marked classical, and the one place anything
/// asks.
///
/// Two things ask: the album page, which draws a classical record as works and
/// movements, and the player, which leaves a classical record unlevelled unless the
/// listener asked otherwise. Both ask per shelf, because a borrowed shelf's answer is
/// its owner's and not this account's.
///
/// **Filed by the shelf the read was for.** A read that lands after the listener has
/// moved to another collection is filed where it belongs instead of being drawn on
/// the wrong one, so nothing here depends on the order reads arrive in. A shelf with
/// no entry has not been read, or could not be, and every record on it reads as not
/// classical.
///
/// `@Observable` and `@MainActor` for the reason ``FavoriteMarks`` is: the album page
/// is a view of this and redraws when an answer lands.
@MainActor
@Observable
public final class ClassicalMarks {
    private var byShelf: [CloudShelf: Set<String>] = [:]

    public init() {}

    /// What a marks read said about one shelf: the album keys marked classical.
    /// Replaces that shelf's answer whole.
    public func file(_ marks: [CloudAlbumMark], for shelf: CloudShelf) {
        byShelf[shelf] = Set(marks.filter { $0.classical == true }.map(\.albumKey))
    }

    /// Drops every shelf's answer. Used on sign-out.
    public func forget() { byShelf = [:] }

    /// Whether a record on a shelf is classical. Matched under every spelling of the
    /// record's album key, as covers are: the desktop hashes whichever album artist
    /// its tags held.
    public func isClassical(_ tracks: [CloudTrack], on shelf: CloudShelf) -> Bool {
        guard let keys = byShelf[shelf] else { return false }
        return AlbumArtKey.spellings(.cover, for: tracks).contains(where: keys.contains)
    }

    /// The same question about the record one track is on. What the player asks.
    public func isClassical(_ track: CloudTrack, on shelf: CloudShelf) -> Bool {
        isClassical([track], on: shelf)
    }
}
