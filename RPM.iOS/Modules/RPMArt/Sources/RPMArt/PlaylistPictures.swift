import Foundation
import CoreGraphics
import RPMKit

/// The picture a playlist wears, from the computer that drew it.
///
/// **It is drawn there, not here.** A generated list wears one of eight made figures, in colours chosen for what
/// the list means. A playlist somebody made wears whatever they chose: four of its records, or a picture from their
/// own disk. All of it is composed on the desktop, with Skia, using the app's own palette. None of that exists on a
/// phone. So the picture crosses the network as plain bytes, and this store fetches it.
///
/// **It has its own store, rather than a part of ``ArtworkStore``.** ``ArtworkStore`` is built around a record. It
/// reads a catalogue of what a shelf holds, so that a wall of six hundred sleeves costs one listing. It keeps a disk
/// copy for the next launch, and it warms the record's own disc beside the sleeve. None of that applies here. A
/// playlist picture is asked for one row at a time, from a tab that holds a few dozen rows, and there is no index to
/// read. So this store does the small job: ask once, hold the answer, and remember a "no". Otherwise a shelf of
/// automatic covers would send a signed request for each row on every scroll.
///
/// Every failure becomes "no picture", never an error on a screen. The row then wears the sleeve of the record it
/// opens on. That is also what a row wears when its list has no picture of its own.
public actor PlaylistPictures {
    private let source: any ArtSource

    public init(source: any ArtSource) {
        self.source = source
        held.totalCostLimit = Self.mostBytesHeld
    }

    /// Eight megabytes of decoded pictures. That is enough for a tab several times over. The pictures are drawn at
    /// a row's size, and there are a few dozen rows.
    public static let mostBytesHeld = 8 * 1024 * 1024

    private final class Entry {
        let art: CoverArt
        init(_ art: CoverArt) { self.art = art }
    }

    /// Emptied by the system when memory runs short, before the phone reaches for the app itself. This is the same
    /// reason ``ArtworkStore`` uses one. `NSCache` is thread-safe, which is what the `unsafe` relies on:
    /// ``pictureInMemory(playlistId:on:edge:)`` reads it from outside the actor.
    private nonisolated(unsafe) let held = NSCache<NSString, Entry>()

    /// The lists that have been asked about and have nothing. Without this, a tab of automatic covers would send a
    /// signed request for each row on every scroll back.
    private var blank: Set<String> = []

    /// One fetch per list, however many rows ask at once. A row drawn four times during a fast scroll is one download.
    /// This holds the BYTES, not a decoded picture, so one download serves every size the row is drawn at.
    private var running: [String: Task<Data?, Never>] = [:]

    /// Changed by ``forget()``. Work that started before a ``forget()`` may not store anything after it.
    private var era = 0

    /// This list's picture at this size, or nil.
    ///
    /// - Parameters:
    ///   - playlistId: a stored playlist's cloud id, or the id a generated list carries in its cut.
    ///   - shelf: whose list. **This is a parameter, not a lookup,** for the same reason as everywhere else in this
    ///     file. A borrowed shelf's lists wear their owner's pictures, and two libraries can hold a list under the
    ///     same id.
    ///   - edge: in **pixels**, not points. The caller knows the screen it is drawing on. This store does not.
    public func picture(playlistId: String, on shelf: CloudShelf, edge: Int) async -> CoverArt? {
        guard !playlistId.isEmpty, edge > 0 else { return nil }

        let address = Self.address(playlistId, shelf)
        let sized = Self.sized(address, edge)

        if let already = held.object(forKey: sized as NSString) { return already.art }
        if blank.contains(address) { return nil }

        // Joined, not started again. One download serves every size, and a row drawn four times in a fast scroll must
        // not start four downloads.
        let mine = era
        let task = running[address] ?? Task<Data?, Never> { [source] in
            guard let url = await source.playlistArt(shelf, playlistId: playlistId)
            else { return nil }

            return try? await source.artwork(at: url)
        }

        running[address] = task
        let bytes = await task.value
        running[address] = nil

        // The store was emptied while this was in flight. Holding the picture now would put a picture from the
        // collection that was just left into the one the user is looking at.
        guard mine == era else { return nil }

        guard let bytes, let image = Thumbnail.of(bytes, edge: edge) else {
            // A picture that arrived but cannot be decoded is as good as none. It is remembered as none, because asking
            // again would fetch the same bytes.
            blank.insert(address)
            return nil
        }

        // Decoded straight to the size the row draws it at, not kept whole and shrunk. The composed picture is 640
        // pixels across, and a row is forty points wide. Holding a few dozen rows at full size would use the whole
        // budget.
        let art = CoverArt(image: image, colours: Thumbnail.colours(of: image))
        held.setObject(Entry(art), forKey: sized as NSString,
                       cost: image.width * image.height)

        return art
    }

    /// The picture ``picture(playlistId:on:edge:)`` holds for this list at this size, or nil. It is read at once, from
    /// any thread, so a view can draw it on its first frame instead of its placeholder.
    public nonisolated func pictureInMemory(playlistId: String, on shelf: CloudShelf, edge: Int) -> CoverArt? {
        guard !playlistId.isEmpty, edge > 0 else { return nil }
        return held.object(forKey: Self.sized(Self.address(playlistId, shelf), edge) as NSString)?.art
    }

    private static func address(_ playlistId: String, _ shelf: CloudShelf) -> String {
        shelf.ownerId + "\u{1}" + playlistId
    }

    private static func sized(_ address: String, _ edge: Int) -> String {
        address + "\u{1}" + String(edge)
    }

    /// Everything held is dropped, and anything in flight stops counting. Used on sign-out.
    public func forget() {
        era &+= 1
        held.removeAllObjects()
        blank.removeAll()
        running.removeAll()
    }

    /// One list's picture has changed, for example because somebody chose a new one. The next request fetches it again.
    public func forget(playlistId: String, on shelf: CloudShelf) {
        blank.remove(shelf.ownerId + "\u{1}" + playlistId)
        held.removeAllObjects()
    }
}
