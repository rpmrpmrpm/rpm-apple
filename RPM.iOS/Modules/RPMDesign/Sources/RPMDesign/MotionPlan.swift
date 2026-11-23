import CoreGraphics

/// What moves on the screen, and how much is drawn for it, while the phone saves power or not.
///
/// **Smooth or still, never in steps.** Anything that moves is drawn on every frame of the display.
/// While the phone saves power the app draws less (fewer pixels, fewer steps, fewer moving
/// pictures), not fewer frames: a rate below the display's does not divide it evenly, so the
/// motion would arrive in steps of uneven length. What answers the music stays live.
///
/// Views read the plan from the environment (`EnvironmentValues.motionPlan`, in `RPMSharedUI`)
/// and not the power state itself, so one value decides for the whole app. The Android app has
/// the same plan with the same fields (`MotionPlan`).
///
/// The glass is not part of the plan: it looks the same in both states.
public struct MotionPlan: Equatable, Sendable {
    /// How the room behind the player is drawn.
    public enum StageRoom: Equatable, Sendable {
        /// At the screen's own pixels, on every frame of the display.
        case full

        /// At `scale` of the screen's size on each side and then magnified, on every frame of the
        /// display. A quarter scale draws one pixel in sixteen.
        case reduced(scale: CGFloat)

        /// One frame that stays. The colours still change to a new record's colours. The bars
        /// beside the cover carry the music.
        case still
    }

    /// How the room behind the player is drawn.
    public let stageRoom: StageRoom

    /// Whether the rooms behind cards (the home banner, the pages of artists, albums and
    /// playlists) move. When false they keep one frame, and their colours still change.
    public let cardRoomsMove: Bool

    /// How many steps a marched look takes along each ray.
    public let marchSteps: Int

    /// The share of the screen's size, on each side, that a stage look draws at before it is
    /// magnified.
    public let lookScale: CGFloat

    /// Whether loops that only decorate (and answer nothing) run.
    public let decorativeLoops: Bool

    /// How the room behind the player is drawn while the phone saves power.
    ///
    /// **Still, and not ``StageRoom/reduced(scale:)``, until it is measured on a phone.** The
    /// reduced room is drawn in a small drawing group that is then magnified. It only saves work
    /// if the drawing group is drawn at the small size, and that cannot be checked without a
    /// device. The reduced path is complete in `RoomView` (`RPMSharedUI`): to use it, set this to
    /// `.reduced(scale: MotionPlan.reducedScale)`.
    public static let savingStageRoom: StageRoom = .still

    /// The scale for ``StageRoom/reduced(scale:)``: a quarter on each side.
    public static let reducedScale: CGFloat = 0.25

    /// The plan for the phone's power state. `saving` is true in Low Power Mode.
    public init(saving: Bool) {
        stageRoom = saving ? Self.savingStageRoom : .full
        cardRoomsMove = !saving
        marchSteps = saving ? 32 : 64
        lookScale = saving ? 0.5 : 1
        decorativeLoops = !saving
    }

    /// Everything moves and is drawn in full. The plan where nothing sets one, and on the TV.
    public static let full = MotionPlan(saving: false)
}
