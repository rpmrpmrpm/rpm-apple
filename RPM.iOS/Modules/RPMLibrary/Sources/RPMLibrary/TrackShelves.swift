import Foundation
import RPMKit

/// The shelf each track the phone has seen came from: the user's own, or a shared one.
///
/// **This is read on the audio path.** For that reason it uses a lock around a
/// dictionary. It is not an actor, and it is not `@MainActor`. The look-ahead opens the
/// next track on whatever thread the player uses. If that code had to switch to an
/// actor to read the map, the audio would have to wait for the switch.
///
/// Entries are never removed. Each id takes only a few dozen bytes. A record that is
/// still playing must keep playing after its shelf is closed. The server decides
/// whether playback may continue. It refuses the next signature request when access
/// has ended.
///
/// **The shelf shown on screen is not stored here.** That is view state. It changes
/// with a tap, and nothing below the UI needs it. Screens follow the shelf on screen.
/// Playback follows the record. Keeping the two apart in the code enforces the
/// separation.
public final class TrackShelves: Sendable {
    private let owners = Mutex<[String: String]>([:])

    public init() {}

    /// Records which shelf a listing's tracks came from.
    ///
    /// Only a borrowed shelf is recorded. The user's own tracks are the default answer.
    /// Storing an entry for each of them would copy the whole library into the map
    /// without adding information.
    public func hold(_ shelf: CloudShelf, tracks: [CloudTrack]) {
        guard !shelf.isOwn else { return }

        owners.withLock { owners in
            for track in tracks { owners[track.rpmId] = shelf.ownerId }
        }
    }

    /// The shelf a track came from. `.own` is returned for the user's own tracks, and
    /// also for a track this map has never seen.
    public func shelf(of rpmId: String?) -> CloudShelf {
        guard let rpmId, !rpmId.isEmpty else { return .own }
        guard let owner = owners.withLock({ $0[rpmId] }) else { return .own }
        return .of(owner)
    }

    /// The shelf an album is on, read from its first track. An album with no tracks
    /// returns `.own`. This is the safe default.
    public func shelf(ofAlbum album: CloudAlbum?) -> CloudShelf {
        guard let first = album?.tracks.first else { return .own }
        return shelf(of: first.rpmId)
    }

    /// Called on sign-out. The map belongs to the library it was built from.
    public func forget() {
        owners.withLock { $0.removeAll() }
    }
}

/// A value behind a lock.
///
/// `Synchronization.Mutex` needs macOS 15 and iOS 18. The minimum deployment targets
/// of this package are macOS 14 and iOS 17. This type has the same shape as
/// `Mutex`. When the minimum targets are raised, this type can be deleted and the
/// standard `Mutex` imported in its place.
struct Mutex<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let box: Box

    private final class Box { var value: Value; init(_ v: Value) { value = v } }

    init(_ value: Value) { box = Box(value) }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&box.value)
    }
}
