import SwiftUI
import RPMSharedUI

/// Builds its content in its own body, not in the body of the view that made it.
///
/// **What the content reads is then this view's dependency, not its parent's.** A value that
/// ``RootView`` reads from an observable model while its body runs makes the whole root run again
/// when the value changes. With the root, every page kept open in its navigation stacks is built
/// again. The player changes on every change of track and on every play and pause, so whatever
/// reads the player is built inside one of these. Such a change then runs only this view again.
///
/// The parent's own changes still reach the content: when the parent runs again, it makes a new
/// one of these with a new closure, and SwiftUI runs that again too.
struct OwnReads<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View { content() }
}

/// Rests the rooms of a page while another page covers it in its navigation stack.
///
/// A navigation stack keeps every page that was opened, under the page on top. Their rooms would
/// go on drawing frames that nobody sees. The stack tells a page when it goes out of sight and
/// when it comes back (`onDisappear` and `onAppear`), and this sets
/// ``SwiftUI/EnvironmentValues/roomsRest`` from that. It only adds to what the views above it set:
/// a page of a tab that is not shown rests whether it is covered or not.
private struct RestsWhileCovered: ViewModifier {
    @Environment(\.roomsRest) private var resting

    /// Whether the page is in sight. True at first, because a page opens on top of its stack.
    @State private var inSight = true

    func body(content: Content) -> some View {
        content
            .environment(\.roomsRest, resting || !inSight)
            .onAppear { inSight = true }
            .onDisappear { inSight = false }
    }
}

extension View {
    /// Rests this page's rooms while another page covers it. See ``RestsWhileCovered``.
    func restsWhileCovered() -> some View {
        modifier(RestsWhileCovered())
    }
}
