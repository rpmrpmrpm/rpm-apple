import SwiftUI

public extension View {
    /// A `List` row with none of the usual list row styling: no fill, no inset, no separator.
    ///
    /// **Why a page is a `List` at all**, when it draws none of what a list draws: the
    /// swipe actions on a row. `swipeActions` is the framework's own gesture and it works
    /// only inside a `List`. Outside a `List` it does nothing and gives no warning. This
    /// modifier makes the page look the same as it would in a `LazyVStack`.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }
}
