import Foundation

/// How many times refresh has been pressed on each generated list, on this phone.
///
/// **A number per list, and nothing else.** A generated list is sent as a run of several
/// lists' worth (see ``GeneratedLists/window(_:shows:reading:)``). This type says which
/// slice of the run the listener is on. Nothing here holds songs. The run comes from the
/// computer, and the slice is simple arithmetic. A count kept for a run that has since
/// been replaced still gives a valid slice of the new run.
///
/// **This phone's own count, and it stays on this phone.** The computer keeps its own
/// count, and the two are not synchronised. Pressing refresh on the phone does not move
/// the computer's list, and the computer starting up does not move the phone's slice. So
/// the two screens can show different slices of the same run. The benefit is that a
/// refresh answers at once, with no network and nothing that can fail.
///
/// **Kept per list id.** The computer sends the id, and it is derived from what the list
/// is. So a count still works after a re-cut with different songs in it. A list that is
/// no longer offered is simply never asked about.
///
/// Not `Sendable`: it holds the defaults it writes to, which are not. It lives on the
/// model that owns the playlists tab and is used only from that one place.
public struct GeneratedListReadings {
    /// One key holds all of them. A key per list would leave a defaults file with a row
    /// per mood per genre per decade, about eighty on a real collection, and nothing
    /// ever clears them.
    private static let key = "rpm.generatedListReadings"

    private let store: UserDefaults
    private var byList: [String: Int]

    /// - Parameter store: where to keep them. The app passes the standard defaults. A test
    ///   passes a suite of its own, so that a test cannot change the slices on a real phone.
    public init(store: UserDefaults = .standard) {
        self.store = store
        self.byList = (store.dictionary(forKey: Self.key) as? [String: Int]) ?? [:]
    }

    /// Which slice this list is on. A list nobody has pressed is at zero, which is the
    /// first slice of the run. That is the best slice, and it is what the computer shows.
    public func reading(of list: String) -> Int { byList[list] ?? 0 }

    /// Every reading, as ``GeneratedLists/sets(_:against:shelf:readings:)`` expects them.
    public var all: [String: Int] { byList }

    /// Moves one list on by one slice and saves the new value.
    ///
    /// The count goes up without limit, rather than wrapping at the number of slices. How
    /// long a run is depends on the cut, and the cut is replaced whenever the computer
    /// runs. A count that was wrapped against an old run would point to a different slice
    /// of the new run, for no reason that the listener could see. The window wraps instead.
    @discardableResult
    public mutating func step(_ list: String) -> Int {
        let next = reading(of: list) + 1
        byList[list] = next
        store.set(byList, forKey: Self.key)
        return next
    }
}
