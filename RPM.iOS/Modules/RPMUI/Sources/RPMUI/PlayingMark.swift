import SwiftUI

/// Which song has the playing mark: the white bar in a list's margin.
///
/// **A reader, not a value.** The song changes on every change of track. A page that is given the
/// song as a value is built again by its parent each time, and so is every page kept open under it
/// in a navigation stack. This reader is set once, at the root of the app. The views that draw the
/// mark call it in their own body (``IfPlaying``), so a change of track draws only them again. The
/// app's reader reads an observable model, so SwiftUI records the dependency in the view that
/// calls it and not in the root.
public final class PlayingMark: Sendable {
    private let read: @MainActor @Sendable () -> String?

    /// - Parameter read: the `rpmId` of the song with the mark, or nil. Called in the body of
    ///   each view that draws the mark.
    public init(_ read: @escaping @MainActor @Sendable () -> String?) {
        self.read = read
    }

    /// The `rpmId` of the song with the mark, or nil when no song has it. Read it in the body of
    /// the view that draws the mark, and nowhere above it.
    @MainActor public var rpmId: String? { read() }

    /// No song has the mark. For a view that the app has not given a reader, such as a preview.
    public static let nobody = PlayingMark { nil }
}

private struct PlayingMarkKey: EnvironmentKey {
    static let defaultValue = PlayingMark.nobody
}

extension EnvironmentValues {
    /// Which song has the playing mark. See ``PlayingMark``.
    ///
    /// Set it once, with one object that lives as long as the screens. A new object on every pass
    /// of a body is a change of the environment, and every view that reads it would be drawn
    /// again with it.
    public var playingMark: PlayingMark {
        get { self[PlayingMarkKey.self] }
        set { self[PlayingMarkKey.self] = newValue }
    }
}

/// Draws its content with whether the song `rpmId` has the playing mark.
///
/// It reads ``SwiftUI/EnvironmentValues/playingMark`` in its own body. A change of track then
/// draws this small view again, and not the page that holds it.
struct IfPlaying<Content: View>: View {
    /// The song this content is for. Nil for a row that is not a song: it never has the mark.
    let rpmId: String?

    let content: (Bool) -> Content

    @Environment(\.playingMark) private var mark

    init(rpmId: String?, @ViewBuilder content: @escaping (Bool) -> Content) {
        self.rpmId = rpmId
        self.content = content
    }

    var body: some View {
        content(rpmId != nil && mark.rpmId == rpmId)
    }
}
