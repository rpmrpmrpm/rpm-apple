import SwiftUI

/// A row that is **moved** by a swipe and not laid out again inside it.
///
/// `List` makes room for a swipe by narrowing the cell. A row whose middle is
/// `maxWidth: .infinity` answers by re-flowing: the title's column shrinks, and whatever is
/// flush right (a duration, a time) is squeezed out of the row. Under a finger, this looks like
/// the row shrinking from the right, which is not what the hand did. The hand pushed it
/// sideways.
///
/// So the row is given its width once, from the list's own width, and keeps it. A narrowed cell
/// then moves and clips the row instead of rearranging it, as in the other lists in the app.
///
/// **Two halves, and both are needed.** The list measures itself and hands the number down;
/// each row asks for it. The width is the list's, never the cell's: the cell is the thing that
/// shrinks, and measuring it would measure the problem.
private struct RowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// What a row is laid out at, or nil before the list has been measured. That lasts one
    /// frame, and `frame(width: nil)` gives a row with the normal, unpinned behaviour.
    var rowWidth: CGFloat? {
        get { self[RowWidthKey.self] }
        set { self[RowWidthKey.self] = newValue }
    }
}

private struct RowsKeepTheirWidth: ViewModifier {
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.rowWidth, width)
            // **Behind the list, so this cannot change what it measures.** A background is
            // given the size that its host already chose; a `GeometryReader` around the list
            // would be given the whole screen and would give the list its own size.
            .background {
                GeometryReader { space in
                    Color.clear
                        .onAppear { width = space.size.width }
                        .onChange(of: space.size.width) { _, now in width = now }
                }
            }
    }
}

private struct KeepsItsWidth: ViewModifier {
    @Environment(\.rowWidth) private var width
    @Environment(\.editMode) private var editMode

    func body(content: Content) -> some View {
        // **Not while the list is being rearranged.** The cell is then narrowed for the drag
        // handle and stays narrowed. That room belongs to the handle and is not a swipe passing
        // through: a row pinned to the list's width would run under the handle and lose its own
        // margins. Unpinned, the row fits the cell and its text gives up the room. The list's own
        // edit mode is read when the row is drawn, so it does not matter which of the two
        // changes first.
        if editMode?.wrappedValue.isEditing == true {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Leading, because a swipe from the left takes its room from the left: the row
            // follows the edge it is pinned to and goes off the other one.
            content.frame(width: width, alignment: .leading)
        }
    }
}

public extension View {
    /// Measures this list and hands its width down to the rows in it. See
    /// ``KeepsItsWidth``, which is the other half.
    func rowsKeepTheirWidth() -> some View { modifier(RowsKeepTheirWidth()) }

    /// Lays this row out at the list's width whatever the cell is doing, so a swipe moves it
    /// and does not re-flow it.
    func keepsItsWidth() -> some View { modifier(KeepsItsWidth()) }
}
