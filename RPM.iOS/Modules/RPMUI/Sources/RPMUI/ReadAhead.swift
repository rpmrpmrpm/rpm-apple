import Foundation

/// Loads the pictures of the items just outside a lazy grid's view, so they are ready when those
/// items scroll in. The Android app's `PreloadAhead` does the same.
///
/// A tile asks for its picture only when it appears, and a picture from the disk still has to be
/// read and decoded, so a tile that scrolled in was blank for a moment, even for a cover seen
/// before. Here the items within `ahead` of the ones on screen are asked for while the grid stands
/// or scrolls.
///
/// **`load` must ask exactly what the tile asks** (the same item at the same size), or the tile
/// misses the store's memory and the work is wasted.
///
/// A reference held in `@State`, and not observable: an item appearing must not draw the grid
/// again.
@MainActor
final class ReadAhead {
    /// The items on screen, by position in the grid.
    private var shown = Set<Int>()

    /// The items asked for in the current window. Only the window is remembered, so an item
    /// scrolled far away and back is asked for again: the store's memory may have let it go.
    private var asked = Set<Int>()

    /// How many items the grid held when the positions were read. A grid with other items in it
    /// (a new order, a search) starts again.
    private var count = 0

    /// - Parameters:
    ///   - index: the item's position in the grid.
    ///   - count: how many items the grid holds.
    ///   - ahead: how many items past the screen to load, on each side: four rows of the grid.
    ///   - load: asks the store for the picture of the item at a position.
    func appeared(_ index: Int, count: Int, ahead: Int,
                  load: @escaping @MainActor (Int) async -> Void) {
        if count != self.count {
            self.count = count
            shown = []
            asked = []
        }
        shown.insert(index)

        guard let first = shown.min(), let last = shown.max() else { return }
        let from = max(0, first - ahead)
        let to = min(count - 1, last + ahead)
        asked = asked.filter { $0 >= from && $0 <= to }

        // Ahead of the screen first, then behind it, nearest first on each side.
        var wanted: [Int] = []
        if last < to { wanted += Array((last + 1)...to) }
        if from < first { wanted += Array((from..<first).reversed()) }
        wanted.removeAll { asked.contains($0) || shown.contains($0) }
        guard !wanted.isEmpty else { return }
        asked.formUnion(wanted)

        Task {
            for index in wanted {
                guard index < self.count else { return }
                await load(index)
            }
        }
    }

    func disappeared(_ index: Int) {
        shown.remove(index)
    }
}
