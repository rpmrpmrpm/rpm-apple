import SwiftUI
import RPMDesign

/// The two parts of a screen that the user puts away by pulling it down: the screen, and the
/// grip that the finger drags.
///
/// Both come from ``ScreenPull``, and neither of them stores any state. The offset is the
/// travel of the value, and the gesture writes only that travel. A screen that wants this
/// behaviour uses these two modifiers and nothing else. No other place holds a flag that says
/// whether the screen is leaving.
public extension View {
    /// **The screen.** Everything that the pull moves is inside this, including the background
    /// of the screen. If the background stayed in place while the content moved, the two would
    /// be one screen split into two places.
    func pulledDown(_ pull: ScreenPull) -> some View {
        offset(y: pull.down)
    }

    /// **The grip.** The whole strip is the target, not only the bar drawn in it. The user can
    /// pull it down to put the screen away, or tap it.
    ///
    /// The travel is measured **against the window, not against the grip**. The grip is inside
    /// the view that this drag moves, so the grip's own coordinate space moves with the screen.
    /// For example, the finger reads 90 points down, so the screen moves 90 points down and the
    /// grip moves with it. The next reading is taken in a space that has just moved by the same
    /// amount, so it is zero. The screen then moves back, the space moves back, and the reading
    /// is 90 again. The screen would jump between two positions on every frame. The gesture needs
    /// a space that it cannot move, and `.global` is the only one here.
    ///
    /// **The space must be applied to a value that uses it.** Naming `.global` and then reading
    /// `translation` does not leave the grip's space. The coordinate space is applied only to
    /// `location`, `startLocation` and `predictedEndLocation` of a drag. `translation` and
    /// `predictedEndTranslation` stay in the space of the view that the gesture is attached to,
    /// which is the grip, which is inside the view that moves. So this code reads the two
    /// positions and lets ``ScreenPull`` do the subtraction. ``ScreenPull`` needs nothing else:
    /// see ``RPMDesign/ScreenPull/follow(to:from:)``.
    ///
    /// Letting go far enough does not start an animation. ``ScreenPull/putAway()`` leaves the
    /// travel as it is, and the removal transition carries the screen on down from there. A
    /// close that must wait for an animation to finish can fail to happen.
    func pullGrip(_ pull: Binding<ScreenPull>) -> some View {
        contentShape(Rectangle())
            .onTapGesture { pull.wrappedValue.putAway() }
            .gesture(
                DragGesture(minimumDistance: ScreenPull.slip, coordinateSpace: .global)
                    .onChanged {
                        pull.wrappedValue.follow(to: $0.location.y, from: $0.startLocation.y)
                    }
                    .onEnded { thrown in
                        // Where the finger actually stopped. This can differ from the last
                        // position reported by `onChanged`.
                        pull.wrappedValue.follow(to: thrown.location.y,
                                                 from: thrown.startLocation.y)

                        let gone = pull.wrappedValue.letGo(
                            heading: thrown.predictedEndLocation.y,
                            from: thrown.startLocation.y)

                        // If the pull is too short, the screen returns **with a spring and
                        // not by plain assignment**. Otherwise the screen would follow the
                        // hand down and then jump back, so only one direction is animated.
                        if gone { pull.wrappedValue.putAway() }
                        else { withAnimation(.spring(duration: 0.3)) { pull.wrappedValue.home() } }
                    })
    }
}

public extension AnyTransition {
    /// Moves in from below the window and out past its bottom edge, for a screen that the user
    /// puts away by pulling it down.
    ///
    /// **It uses the window's height, not the view's.** `.move(edge: .bottom)` moves a view by its
    /// own layout height. These screens are laid out inside the safe area but draw their
    /// background to the edge of the glass, so that move would stop short by the size of the
    /// insets. When the screen is closed by a tap, the grip would stay at the bottom of the screen
    /// until the transition ends and the view disappears. A drag does not show this problem,
    /// because the screen is already that far down when the finger lifts.
    @MainActor static var belowWindow: AnyTransition {
        .offset(y: RPMSafeArea.window.height)
    }
}
