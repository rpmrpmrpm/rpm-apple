import UIKit

/// Haptic feedback for gestures.
///
/// Ported from `RPM.Mobile/Presentation/Haptics.cs`.
///
/// When a gesture changes something under a finger, the finger covers the place where the
/// change would be shown. For example, the thumb is over the row that was just picked up.
/// **Haptic feedback is the one channel that reaches the finger itself.**
///
/// The generators are kept and prepared again after each use, and are not created for every
/// tap. The Taptic engine needs a short time to wake. A generator that is not prepared responds
/// late, and the delay is noticeable.
@MainActor
public enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let firm = UIImpactFeedbackGenerator(style: .medium)
    private static let selection = UISelectionFeedbackGenerator()

    /// A row has been picked up.
    public static func pick() {
        light.impactOccurred()
        light.prepare()
    }

    /// Something has moved one place, or crossed the point where letting go would trigger an
    /// action.
    public static func tick() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// The action is done.
    public static func commit() {
        firm.impactOccurred()
        firm.prepare()
    }
}
