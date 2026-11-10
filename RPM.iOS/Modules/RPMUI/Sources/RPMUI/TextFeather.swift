import SwiftUI

/// A soft dark outline round text: a shadow that is not cast anywhere, only feathered, so text stays
/// readable where the picture under it is bright. The artist page asks for it for everything on it
/// (``SwiftUI/EnvironmentValues/textFeather``); elsewhere text is drawn as it is. The Android
/// phone's `LocalTextFeather` is the same outline.
///
/// The parts of the app that draw text the artist page shows (a kicker, a sleeve's caption, a row of
/// songs) put ``SwiftUI/View/feathered()`` on that text, so it takes the outline there and only there.
private struct TextFeatherKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the text below is drawn with its soft outline. See ``TextFeatherKey``.
    var textFeather: Bool {
        get { self[TextFeatherKey.self] }
        set { self[TextFeatherKey.self] = newValue }
    }
}

/// The outline, where the page asks for it.
private struct Feathered: ViewModifier {
    @Environment(\.textFeather) private var on

    /// How far it is feathered, and how dark it is.
    private static let reach: CGFloat = 3
    private static let darkness = 0.55

    func body(content: Content) -> some View {
        if on {
            content.shadow(color: .black.opacity(Self.darkness), radius: Self.reach)
        } else {
            content
        }
    }
}

extension View {
    /// The soft outline round this text, on a page that asks for it. Put it on text only: on a
    /// picture it would be a drop shadow round the picture's edge.
    func feathered() -> some View { modifier(Feathered()) }
}
