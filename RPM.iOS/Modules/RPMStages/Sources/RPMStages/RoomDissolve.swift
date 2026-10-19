import Foundation

/// A room changing colour, as a travel that can be asked where it is rather than as a
/// value somebody has to remember to advance.
///
/// ## Why it is a travel and not a stored colour
///
/// The Uno app eases its palette on `CompositionTarget.Rendering`, the compositor's own
/// frame clock. That clock runs whenever the stage is up and knows nothing about the
/// music. Advancing the ease inside `RoomReader`'s analysis loop would not work here,
/// because **that loop does not turn until the engine has named a sample rate**. Nothing
/// is written to the tap while the sheet is opened on a paused track, or before the first
/// block is decoded, or at all while the sound goes to a speaker in another room. In all
/// of those cases the palette would never advance, and the room would stay on the app's
/// own blue while a sleeve full of colour sits on top of it.
///
/// So the dissolve is derived rather than pushed: it holds where it came from, where it
/// is going and when it left, and answers ``read(_:)`` at whatever instant the frame is
/// being drawn. Nothing has to tick it, so a silent engine cannot freeze it. ``RoomRamp``
/// has the same shape for the bands, for the same reason.
public struct RoomDissolve: Sendable, Equatable {
    /// Where the room was when this change of record arrived.
    public let from: RoomPalette

    /// ...and the colours it is heading for.
    public let to: RoomPalette

    /// When it set off, on whichever monotonic clock ``read(_:)`` is asked with.
    public let at: Double

    /// How quickly it closes the gap, per second. The value is the same as in the Uno app
    /// (`2.4`), which takes about a second in total. That is long enough for a change of
    /// record to look like a dissolve and not a cut, and short enough that it has arrived
    /// by the time anybody looks.
    public static let rate: Float = 2.4

    /// A room that has never been told a colour: the app's own blue, standing still.
    public static let still = RoomDissolve(from: .fallback, to: .fallback, at: 0)

    public init(from: RoomPalette, to: RoomPalette, at: Double) {
        self.from = from
        self.to = to
        self.at = at
    }

    /// The colours as they stand at `now`.
    ///
    /// The curve is exponential, so it does not depend on the frame rate: whether it is asked
    /// once a second or a hundred and twenty times, it is in the same place at the same instant.
    public func read(_ now: Double) -> RoomPalette {
        let travelled = now - at
        guard travelled > 0 else { return from }

        let k = 1 - exp(-Float(travelled) * Self.rate)
        return from.eased(to: to, by: min(1, k))
    }

    /// This dissolve, redirected at `target`.
    ///
    /// **From where the room actually stands**, not from where the last change started:
    /// a record changed twice inside a second would otherwise snap back to the colour
    /// before last and set off again. Asking for the colours it is already headed for
    /// changes nothing, so a view that hands the same sleeve over on every appearance
    /// does not restart the dissolve.
    public func toward(_ target: RoomPalette, at now: Double) -> RoomDissolve {
        target == to ? self : RoomDissolve(from: read(now), to: target, at: now)
    }
}
