import CoreGraphics
import Foundation

/// A photographed record, and **whether it is the whole record or only its label**.
///
/// The desktop app's `DiscStamp` asks the same question of the same pixels. The answer decides three
/// things at once: whether the drawn pressing shows underneath, whether the record wobbles, and whether
/// the picture is drawn there at all. It is kept as a type of its own, so a caller cannot hold a scanned
/// disc without the question having been answered. There is no initialiser that takes the flag directly.
///
/// **The answer is read from the picture, not remembered from where the picture came from.** A folder's
/// disc.png may be written by the album editor, by the cover search, by an import, or by hand. By the time
/// it reaches a phone, nobody is left to ask. The alpha at four fifths of the radius gives the answer
/// whenever it is asked. A label stamp is transparent there. A CD and a whole photographed side are not.
public struct ScannedDisc: @unchecked Sendable {
    public let image: CGImage

    /// The picture is the whole record, and it replaces the pressing. False for a label. A label is worn
    /// on the pressing that RPM draws for itself.
    public let coversRecord: Bool

    /// Where on the radius the question is asked. This is the desktop app's `DiscStamp.RimFraction`:
    /// outside any label, and inside the rim of any disc.
    private static let rim: Double = 0.8

    /// How many points around that ring are sampled. The desktop app uses the same value, as `RimSamples`.
    private static let samples = 64

    /// Reads the picture and answers the question. This is the only way to create one.
    public init(_ image: CGImage) {
        self.image = image
        self.coversRecord = Self.covers(image)
    }

    /// **Returns true for anything that cannot be read.** A picture that cannot be decoded is not drawn
    /// either, so the value does not change what is shown.
    private static func covers(_ image: CGImage) -> Bool {
        let edge = min(image.width, image.height)
        let radius = Double(edge) / 2 * rim
        guard radius >= 4 else { return true }

        // An alpha-only read of the whole picture. It takes one pass, with one byte per pixel, rather
        // than a context for each sample.
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 255, count: width * height)

        let read: Bool = alpha.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard read else { return true }

        let cx = Double(width) / 2, cy = Double(height) / 2
        var opaque = 0, taken = 0

        for i in 0..<samples {
            let angle = 2 * Double.pi * Double(i) / Double(samples)
            let x = Int((cx + radius * cos(angle)).rounded())
            let y = Int((cy + radius * sin(angle)).rounded())
            guard x >= 0, y >= 0, x < width, y < height else { continue }

            taken += 1
            if alpha[y * width + x] >= 128 { opaque += 1 }
        }

        return taken == 0 || opaque * 2 >= taken
    }
}

/// Everything a record wears: the colour it is pressed in, the album art on its label, and the
/// photographed CD that replaces the drawn disc entirely where there is one.
///
/// The desktop app's `RecordChange.cs` does the same job.
///
/// **One value, not three, because they are one thing.** The three parts arrive separately. The sleeve
/// is decoded in one pass, and the CD is fetched in another. But they must go on together. Otherwise the
/// record would wear half of one album and half of another for as long as the gap lasts.
public struct RecordFace: Sendable {
    /// Which record this is. **It is the identity.** The next track of an album is the same record, and
    /// nothing about the disc on the deck changes for it.
    public let album: String

    public let hue: RGB?
    public let label: CGImage?
    public let cd: ScannedDisc?

    /// An empty deck: no album, no colour, no pictures. This is what the record wears when nothing is
    /// playing. It is the house pressing and the rpm stamp.
    public static let none = RecordFace(album: "", hue: nil, label: nil, cd: nil)

    public init(album: String, hue: RGB?, label: CGImage?, cd: ScannedDisc?) {
        self.album = album
        self.hue = hue
        self.label = label
        self.cd = cd
    }

    /// Whether this is the same RECORD as the other face. That is not the same question as whether the
    /// two values are equal.
    ///
    /// Every track of an album hands over a freshly decoded copy of the same sleeve. Comparing the
    /// pictures would treat each track as a new record. The disc would be taken off the deck and an
    /// identical one put back on.
    ///
    /// Whether there IS a CD counts, though. What matters is whether there is one at all, not which one,
    /// because each track decodes a fresh copy. Without this check, a CD that arrives just after the
    /// record has been dressed for its album would be answered with "same record, nothing to do", and the
    /// CD would be dropped.
    ///
    /// **Whether the CD covers the record** is the other half of the same point. A label scan and a
    /// whole-disc scan are two different records to look at. One is worn on the pressing, and the other
    /// replaces it. Swapping one for the other must count as a change of record. It must not be a picture
    /// quietly exchanged on the deck.
    public func isSameRecord(as other: RecordFace) -> Bool {
        hue == other.hue
            && (cd == nil) == (other.cd == nil)
            && cd?.coversRecord == other.cd?.coversRecord
            && (label == nil) == (other.label == nil)
            && album.caseInsensitiveCompare(other.album) == .orderedSame
    }
}

/// Where the record is.
///
/// **Two of these are journeys, not places.** The disc is visible for the whole of both journeys. So
/// neither one is a moment when its face may change.
public enum Deck: Sendable {
    /// Off the deck: shrunk into the corner and faded to nothing. This is the only place where a record
    /// may be re-dressed.
    case off
    /// Flying down onto the deck, fading up as it comes.
    case dropping
    /// On the deck, in plain sight.
    case on
    /// Flying off to the corner, fading down as it goes.
    case lifting
}

/// Where to send the record, if anywhere.
public enum Flight: Sendable, Equatable { case stay, lift, drop }

/// What is to be done: put the wanted face on, and/or send the record somewhere. A move with
/// ``Move/dress`` set can only come back while the record is ``Deck/off``. That is the one guarantee
/// this whole file exists to make.
public struct Move: Sendable, Equatable {
    public let dress: Bool
    public let fly: Flight

    public static let nothing = Move(dress: false, fly: .stay)
}

/// The rule that a record change obeys, with no record in it.
///
/// **A record's face only changes where nobody can see it change.** That is the whole rule. If one album
/// replaces another on a turning deck, the change is visible. The disc lifts off, its colour, label and
/// CD are swapped while it is away, and then it comes back down. A cross-fade between two faces on a disc
/// that is still turning would look like a record changing its clothes in front of the listener.
///
/// The rule applies to the ALBUM, not the track. The next track of the same record is the same record. So
/// a playlist that moves from one album into another follows the same rule. Playlists do not need to be
/// mentioned here.
///
/// **It has no pictures in it, which is what makes it testable.** A sequence of arrivals can be fed to it
/// in any order, and the guarantee can be checked directly. `RecordChangeTests` does this. The desktop
/// app's version has two more facts that this version has no source for. One is a cue/park pair for a
/// stopped deck. The other is that a pressing must be in hand before a face may go on. Here the disc stays
/// on screen for as long as the stage does, and the caller waits for the press while the record is off.
/// Both points are stated where they are relied on, not modelled here.
public struct RecordChange: Sendable {
    /// Where the record is right now. It is set here and nowhere else. A flight is ordered by this type,
    /// so this type is what knows that a flight is under way.
    public private(set) var deck: Deck

    /// The face the record should be wearing. The caller uses it to put the face on.
    public private(set) var wanted: RecordFace

    /// The face the record is wearing now. It is written only by ``dressed()``, which the caller may call
    /// only after a move that asked for it.
    public private(set) var worn: RecordFace

    /// - Parameter onDeck: whether a record is already down when this takes over.
    public init(onDeck: Bool = true) {
        deck = onDeck ? .on : .off
        wanted = .none
        worn = .none
    }

    /// The record that belongs on the deck now. **This is a request, never a write.** This type decides
    /// whether a change happens, and when. The caller does not.
    public mutating func wear(_ face: RecordFace) -> Move {
        wanted = face
        return settle()
    }

    /// A flight has finished. The record is now wherever it was going.
    public mutating func landed() -> Move {
        switch deck {
        case .lifting: deck = .off
        case .dropping: deck = .on
        default: break
        }

        return settle()
    }

    /// Records the flight that a ``Move`` ordered. This makes ``deck`` true from the moment a flight is
    /// ordered, not from the moment it is carried out.
    public mutating func flying(_ flight: Flight) {
        switch flight {
        case .lift: deck = .lifting
        case .drop: deck = .dropping
        case .stay: break
        }
    }

    /// The face has been put on. The caller may do this only for a move that asked for it.
    public mutating func dressed() { worn = wanted }

    /// Whether the disc on the deck is the wrong record. This is the only question that starts a flight.
    private var wrongRecord: Bool { !worn.isSameRecord(as: wanted) }

    /// The rule itself. Every arrival ends here. The answer depends only on where the record is. It never
    /// depends on how the record got there, or on how long ago that was.
    private func settle() -> Move {
        switch deck {
        // In the air, and visible for the whole of it. Nothing is decided mid-flight. `landed` asks again
        // as soon as the record is somewhere.
        case .lifting, .dropping:
            return .nothing

        // Off the deck: the one place where a face may change. So this is the only branch that may say so.
        case .off:
            return Move(dress: wrongRecord, fly: .drop)

        // On the deck, where nothing about it may change. If it is the wrong record, it is lifted off first.
        // The change happens while it is off.
        case .on:
            return wrongRecord ? Move(dress: false, fly: .lift) : .nothing
        }
    }
}
