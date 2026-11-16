import CoreGraphics
import Foundation
import ImageIO
import RPMDesign

/// What the record looks like for an album that has no picture of its own disc. It is the desktop
/// app's `DiscStandIn` setting, with the CD as the default here.
public enum DiscStandIn: String, CaseIterable, Sendable {
    /// A plain CD (``BlankDisc``), drawn as a photographed CD is, with the CD's rim and hub over it.
    case cd

    /// The app's own drawn vinyl, with the sleeve on its label.
    case vinyl
}

/// The plain CD that stands in for a record with no disc picture, when the listener has chosen the CD
/// (``DiscStandIn/cd``, the default).
///
/// **It is handed out as a ``ScannedDisc``, the same type as a record's own disc picture.** The picture
/// is opaque at four fifths of the radius, so it reads as a whole CD. Every screen then draws it exactly
/// as it draws a photographed CD: the pressing and the label go, the CD's rim, hub and spindle go on top,
/// and the record does not wobble. No screen needs a separate path for it.
///
/// The picture is the desktop's `Assets/cd-blank.png`: a scan of the data side of a CD, cut round, with
/// the clear centre left transparent.
public enum BlankDisc {
    /// Where the choice is kept, in the user defaults. The phone's profile page and the TV's settings
    /// both write it, and the screens that draw a record read it.
    public static let key = "look.discStandIn"

    /// The choice when none was made.
    public static let initial = DiscStandIn.cd

    /// The stored choice, or ``initial``.
    public static func chosen(in store: UserDefaults = .standard) -> DiscStandIn {
        store.string(forKey: key).flatMap(DiscStandIn.init(rawValue:)) ?? initial
    }

    /// The plain CD when the CD is chosen, and nil when the vinyl is. Nil also when the picture cannot
    /// be read; the record then falls back to the vinyl, which is always there.
    public static func standIn(in store: UserDefaults = .standard) -> ScannedDisc? {
        chosen(in: store) == .cd ? picture : nil
    }

    /// Read once and kept, found or not.
    private static let picture: ScannedDisc? = {
        guard let url = Bundle.module.url(forResource: "cd-blank", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return ScannedDisc(image)
    }()
}
