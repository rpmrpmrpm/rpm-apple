import SwiftUI
import Foundation
import Observation

/// Whether the phone saves power: Low Power Mode.
///
/// A moving room is a full-screen fragment program drawn on every frame of the display, the most
/// expensive thing the app draws, and it redraws the whole screen even while nothing else moves.
/// While the phone saves power it often runs the processor and the GPU slower, and then a scroll or
/// a tap waits behind that work. So while ``isOn`` is true a card's room keeps its picture, as a
/// stopped room does, and the stage's room and the player's spectrum are drawn ``savingRate`` times
/// a second. See ``RoomView``. The Android app does the same while battery saver is on.
///
/// The value follows the system's notification, so a change shows at once. It is always false on
/// the TV, which has no Low Power Mode.
@MainActor
@Observable
public final class PowerSaving {
    /// The one reading for the whole app.
    public static let shared = PowerSaving()

    /// Whether Low Power Mode is on.
    public private(set) var isOn: Bool

    /// How many frames a second a moving picture that must keep moving is drawn while the phone
    /// saves power.
    public static let savingRate: Double = 15

    /// The shortest time between two frames of such a picture while the phone saves power, or nil
    /// for every frame of the display.
    public var frameGap: Double? { isOn ? 1 / Self.savingRate : nil }

    @ObservationIgnored private var watch: (any NSObjectProtocol)?

    private init() {
        #if os(iOS)
        isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
        watch = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, which is where this object lives.
            MainActor.assumeIsolated {
                self?.isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
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
