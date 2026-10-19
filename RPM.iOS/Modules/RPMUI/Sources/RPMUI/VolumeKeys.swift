import AVFoundation
import MediaPlayer
import UIKit
import os

/// Uses the phone's volume buttons to change the volume of the cast speaker.
///
/// Port of `RPM.Mobile/Services/Audio/VolumeKeys.cs`.
///
/// While a cast is running, the phone's own volume has no effect, because no sound
/// comes out of the phone. The speaker's volume is the one that matters. The buttons are
/// **the one control that works without looking at the screen**, which is useful when the
/// phone is in a pocket.
///
/// ## iOS has no volume-button event to subscribe to
///
/// iOS only reports the volume level. `AVAudioSession.outputVolume` is observable, and
/// one button press changes it by one sixteenth. So a press is read as a **difference**
/// (the level now minus the previous level), and the difference is passed on. The level is
/// never used as a position, because the phone and the speaker have unrelated ranges: a
/// phone at 80% must not set the speaker to 80%.
///
/// **After each press the level is parked back in the middle**, so there is always room
/// to go both up and down. Without this, a phone already at full volume would report
/// nothing when the user wants it louder: the press hits the limit and the speaker never
/// hears about it.
///
/// Parking means writing the system volume. The only way to do that is the slider inside
/// `MPVolumeView`, because the `AVAudioSession` property is read-only and there is no
/// other API. Google's Cast SDK uses the same method. The code checks that the slider
/// exists instead of assuming it. If the slider is missing, presses are still read
/// correctly and only parking is lost, which makes the two ends of the range unusable
/// and nothing else.
///
/// The `MPVolumeView` also hides the system volume HUD. That is wanted: the HUD would
/// show the phone's parked level, not the change the user made.
@MainActor
public final class VolumeKeys {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// The level where the phone's volume is parked between presses. It is the middle,
    /// so there are eight steps in each direction before a press reaches a limit.
    private static let parked: Float = 0.5

    /// Smaller than half a step. Below this the level did not really move: it is the
    /// report of our own parking write, or the level settling.
    private static let nudge: Float = 0.01

    /// A change bigger than any run of presses between two reports, so it is not a press.
    ///
    /// A button press changes the level by one sixteenth, and every press is reported.
    /// Three steps at once is already generous. **A larger change is made by the system**:
    /// an incoming call, a route change, headphones plugged in, or the audio session being
    /// reactivated. These restore a level that this class does not know about. If such a
    /// jump were read as a press, the speaker volume would change by half its range
    /// because of a phone call.
    private static let lurch: Float = 0.2

    /// How much to change the speaker volume, in points, with a sign. One press is about
    /// 6, because that is one sixteenth of the phone's range.
    private var step: ((Int) -> Void)?

    private var watching: NSKeyValueObservation?
    private var view: MPVolumeView?

    /// The one control on iOS that can write the phone's volume. It is found once, when
    /// the view is added, because that code always runs on the main thread.
    private var slider: UISlider?

    /// The level the phone had after the last report. A press is measured against it.
    private var last: Float = 0

    /// The phone volume the user had before parking. It is put back when the cast ends.
    /// Negative while not running, which also means "nothing to restore".
    private var restore: Float = -1

    public init() {}

    /// Starts reading the volume buttons.
    public func start(_ step: @escaping (Int) -> Void) {
        guard watching == nil else { return }

        self.step = step

        let session = AVAudioSession.sharedInstance()
        restore = session.outputVolume
        last = restore

        // The view is added before the observer starts, so the slider can be found
        // first. It is placed far off screen: it is only here for its slider.
        // `showsRouteButton` is not used, because it has had no effect since iOS 13
        // (the route picker is `AVRoutePickerView`).
        let view = MPVolumeView(frame: CGRect(x: -4000, y: -4000, width: 1, height: 1))
        view.showsVolumeSlider = true
        self.view = view

        if let host = Self.window() {
            host.addSubview(view)
        } else {
            // Logged because without a window the user only sees that the buttons
            // stop working.
            Self.log.notice("no window to hang the volume view on; the keys will not park")
        }

        // `MPVolumeView` builds its slider in its own initialiser, so it can be found
        // now. It is found once and kept.
        slider = view.subviews.compactMap { $0 as? UISlider }.first

        watching = session.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.levelMoved() }
        }

        // Park now, not at the first press, so the first press in either direction
        // has room. Nothing is audible, because no sound comes out of the phone.
        if slider != nil {
            park()
            last = Self.parked
        } else {
            // The buttons still work, but presses at either end of the phone's range
            // do nothing, and that symptom does not point to this code, so log it.
            Self.log.notice("no volume slider to park with; the ends of its range will not step")
        }

        Self.log.notice("volume keys on, handset was at \(self.restore, format: .fixed(precision: 2), privacy: .public)")
    }

    /// Stops reading the buttons and restores the volume the user had set on the phone.
    public func stop() {
        guard watching != nil else { return }

        watching?.invalidate()
        watching = nil
        step = nil

        // Restore the user's level before the view is removed: the slider is inside
        // the view, and it is the only thing that can write the level.
        if restore >= 0 {
            Self.log.notice("volume keys off, handset back to \(self.restore, format: .fixed(precision: 2), privacy: .public)")
            set(restore)
        }

        restore = -1
        slider = nil

        // The view is removed on the **next** run loop turn, not this one. Writing the
        // slider passes the level to the audio session asynchronously. Removing the view
        // in the same turn could interrupt that write and leave the phone parked at half
        // volume.
        let going = view
        view = nil

        Task { @MainActor in
            going?.removeFromSuperview()
        }
    }

    deinit { }

    /// The phone's level changed. Either a button was pressed, or this is the report of
    /// our own parking write. **Telling these two apart is the purpose of this method.**
    private func levelMoved() {
        guard watching != nil, let step else { return }

        let now = AVAudioSession.sharedInstance().outputVolume
        let moved = now - last

        // This is our own parking write, or a report of an unchanged level. Nobody
        // pressed a button. Acting on it would make the app change the speaker volume
        // by itself, in an endless loop.
        guard abs(moved) >= Self.nudge else {
            last = now
            return
        }

        // The system changed the level, not the user. Use the new level as the
        // reference and do not tell the speaker.
        guard abs(moved) <= Self.lurch else {
            last = now
            if slider != nil { park() }
            return
        }

        // If the phone cannot be parked, its own level is the reference. Presses at
        // the two ends of its range then do nothing. This is reduced behaviour, not
        // wrong behaviour.
        let parking = slider != nil
        last = parking ? Self.parked : now

        var points = Int((moved * 100).rounded())

        // One press is a sixteenth, which rounds to 6, but a report can show a smaller
        // change. It still means a press in that direction.
        if points == 0 { points = moved > 0 ? 1 : -1 }

        if parking { park() }
        step(points)
    }

    /// Sets the phone's own level back to the middle, so the next press in either
    /// direction has room to change it.
    private func park() { set(Self.parked) }

    /// Writes the phone's own level. This is only possible through the slider in the
    /// volume view.
    private func set(_ level: Float) {
        guard let slider else { return }
        slider.value = min(1, max(0, level))
    }

    /// A window to add the volume view to. A slider that is not in a view hierarchy does
    /// not change the system volume.
    private static func window() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }
}
