import Foundation
import CoreGraphics
import QuartzCore
import os.log
import Observation
import RPMAudio

/// The frame clock that the drawn looks run on, and the audio tap they listen to.
///
/// It uses a `CADisplayLink`. The other two apps use the same idea under different names: the Uno
/// phone app drives its looks from `CompositionTarget.Rendering`, because an invalidation
/// requested from inside a draw is dropped while the tree is busy, and the picture would then
/// redraw at the rate of whatever unrelated timer is running. The same applies here: a look needs
/// the screen's own refresh rate, not a timer's.
///
/// **When the look is off screen, the clock must be stopped.** A full-screen look at 60 frames a
/// second is the most expensive thing this app draws, and a phone gets hot from it whether or not
/// anybody is looking. ``start(with:)`` and ``stop(_:)`` are the whole contract, the same one that
/// ``RoomReader`` follows.
@MainActor
@Observable
public final class StageClock {
    /// Incremented once per displayed frame. A look reads it to learn that what it draws has
    /// changed. The arrays it draws from are changed in place, and a picture of 30,000 grains
    /// should not be copied 60 times a second just to signal a change.
    public private(set) var tick = 0

    /// Seconds since the clock started, and how long the last frame took. They are stored and not
    /// passed to a callback, so a look can read them where it draws.
    public private(set) var now: Double = 0
    public private(set) var since: Double = 0

    /// How often the music is measured, in seconds. Forty times a second and not sixty: every look
    /// smooths the spectrum with its own attack and release, and none of them changes within
    /// 25 ms. The picture animates from the clock between measurements.
    private static let listen = 0.025

    /// The longest frame time that a look is given. If the device paused for a second, a look must
    /// not receive a whole second of movement in one step.
    private static let longestFrame = 0.05

    /// Called with a frame of played samples, at the ``listen`` rate. The frame is empty for
    /// silence, and every look must handle that.
    public var hear: (([Float]) -> Void)?

    /// Called on every frame, for a look that has its own motion to integrate or geometry to build.
    /// It is called before ``tick`` changes, so what is drawn is what this call left behind. It
    /// receives the size of the frame that will be drawn.
    public var onFrame: ((CGSize) -> Void)?

    /// The size the look is drawn at, set by the layout. A projection needs the frame's shape, and
    /// the clock is where a frame is prepared.
    public var drawnInto: CGSize = .zero

    /// The frame passed to `hear`. It is one buffer, refilled each time. Otherwise a look reading
    /// at 40 Hz for an hour would make about 144,000 allocations.
    private var frame = [Float](repeating: 0, count: 2048)

    private var link: CADisplayLink?
    private var began: CFTimeInterval = 0
    private var lastFrame: Double = 0
    private var lastListen: Double = 0
    private var sound: RoomSound?

    public nonisolated init() {}

    /// Starts the clock and takes the engine's tap.
    public func start(with player: Player) {
        guard link == nil else { return }

        player.draw(true)
        sound = player.drawing

        began = CACurrentMediaTime()
        now = 0
        lastFrame = 0
        lastListen = -Self.listen

        let beat = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.fire))
        beat.add(to: .main, forMode: .common)
        link = beat
    }

    /// Releases the tap and stops. **The engine keeps one listener**, so a look that is dropped
    /// without calling this leaves the tap running for a picture that nobody is looking at.
    public func stop(_ player: Player) {
        link?.invalidate()
        link = nil
        sound = nil

        player.draw(false)
    }

    fileprivate func frameArrived() {
        now = CACurrentMediaTime() - began
        since = lastFrame > 0 ? min(Self.longestFrame, now - lastFrame) : 0
        lastFrame = now

        if now - lastListen >= Self.listen {
            lastListen = now

            let began = Self.diag ? CACurrentMediaTime() : 0

            if let sound, sound.fill(&frame) { hear?(frame) }
            else { hear?([]) }

            if Self.diag { heard += CACurrentMediaTime() - began; heardTimes += 1 }
        }

        onFrame?(drawnInto)

        tick &+= 1
        count()
    }

    // ── measuring the real frame rate ──

    /// When `RPM_STAGE_DIAG` is set, reports how many frames a look really gets.
    ///
    /// A look that has dropped to a third of the screen's rate does not show it: sand drifting and
    /// sand drifting slowly look the same. `RPM_WALL_DIAG` exists for the record wall for the same
    /// reason, and works in the same way.
    private static let diag = ProcessInfo.processInfo.environment["RPM_STAGE_DIAG"] != nil
    private static let log = Logger(subsystem: "com.rpm.player", category: "stage")

    private var counted = 0
    private var countedFrom: Double = 0
    private var heard: Double = 0
    private var heardTimes = 0

    private func count() {
        guard Self.diag else { return }

        counted += 1
        guard now - countedFrom >= 2 else { return }

        let rate = Double(counted) / (now - countedFrom)
        let listening = heardTimes > 0 ? heard / Double(heardTimes) * 1000 : 0

        // The two parts are reported separately, because different things cause them: listening is
        // arithmetic and the rest is drawing. Knowing which one uses up the frame is the reason to
        // count at all.
        Self.log.notice("""
            \(rate, format: .fixed(precision: 1), privacy: .public) frames a second, \
            \(listening, format: .fixed(precision: 1), privacy: .public) ms listening
            """)

        counted = 0
        countedFrom = now
        heard = 0
        heardTimes = 0
    }

    /// The display link's target, which the run loop holds and the clock does not.
    ///
    /// `CADisplayLink` **retains its target**. If the clock were its own target, it would stay alive
    /// as long as the link is scheduled, and only the clock invalidates the link. That is a
    /// retain cycle. This class breaks it: the run loop holds this object, and this object holds
    /// the clock weakly.
    private final class Ticker: NSObject {
        weak var clock: StageClock?

        init(_ clock: StageClock) { self.clock = clock }

        @objc @MainActor func fire() { clock?.frameArrived() }
    }
}
