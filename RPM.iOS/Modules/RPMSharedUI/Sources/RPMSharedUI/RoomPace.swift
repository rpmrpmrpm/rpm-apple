import SwiftUI
import Foundation
import Observation
import RPMDesign

/// Whether the phone saves power: Low Power Mode.
///
/// This is the one source of the power state. Views do not read it: they read the
/// ``SwiftUI/EnvironmentValues/motionPlan`` that the app makes from it, which says what moves and
/// how much is drawn (``RPMDesign/MotionPlan``). Nothing is drawn at a lower rate while the phone
/// saves power. What moves is drawn on every frame of the display, and less is drawn: a card's
/// room keeps its picture, and the player's room keeps its picture or is drawn at fewer pixels.
/// The Android app does the same while battery saver is on.
///
/// The value follows the system's notification, so a change shows at once. It is always false on
/// the TV, which has no Low Power Mode.
///
/// **The Simulator has no Low Power Mode.** In a debug build, set `RPM_POWER_SAVING=1` in the
/// scheme's environment to make the app behave as if it were on.
@MainActor
@Observable
public final class PowerSaving {
    /// The one reading for the whole app.
    public static let shared = PowerSaving()

    /// Whether Low Power Mode is on.
    public private(set) var isOn: Bool

    /// Whether a debug launch asked to behave as if Low Power Mode were on (`RPM_POWER_SAVING=1`).
    /// Always false in a release build. Read once, because it is fixed for the whole launch.
    private nonisolated static let forced: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["RPM_POWER_SAVING"] == "1"
        #else
        return false
        #endif
    }()

    @ObservationIgnored private var watch: (any NSObjectProtocol)?

    private init() {
        #if os(iOS)
        isOn = Self.forced || ProcessInfo.processInfo.isLowPowerModeEnabled
        watch = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, which is where this object lives.
            MainActor.assumeIsolated {
                self?.isOn = PowerSaving.forced || ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        #else
        isOn = false
        #endif
    }
}

private struct RoomsRestKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the rooms under this view should rest: keep their picture and stop drawing new ones.
    ///
    /// Set where a room is still in the view tree but nobody can see it move: the pages of a tab
    /// that is not shown, the pages under the player while it covers the screen, and the player's
    /// own room while the music is paused. Every ``RoomView`` reads it, so a page does not have to
    /// be told one by one.
    public var roomsRest: Bool {
        get { self[RoomsRestKey.self] }
        set { self[RoomsRestKey.self] = newValue }
    }
}

private struct MotionPlanKey: EnvironmentKey {
    static let defaultValue = MotionPlan.full
}

extension EnvironmentValues {
    /// What moves and how much is drawn under this view. See ``RPMDesign/MotionPlan``.
    ///
    /// The app sets it once, at the top of its views, from ``PowerSaving``, and sets it again when
    /// Low Power Mode changes. Where nothing sets it (the TV, a preview) everything moves.
    public var motionPlan: MotionPlan {
        get { self[MotionPlanKey.self] }
        set { self[MotionPlanKey.self] = newValue }
    }
}
