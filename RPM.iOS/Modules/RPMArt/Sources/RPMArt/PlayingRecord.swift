import CoreGraphics
import RPMDesign

/// The record on the deck: which one it is, and **both** of its pictures.
///
/// It is one value, not three fields side by side. The reason is a rule the turntable follows. The record's
/// face is changed where nobody can see it change, which is off the deck, between the lift and the drop. See
/// `RecordChange`.
///
/// The rule only works if the album and its pictures arrive together. If they are held apart, the album name
/// changes the moment a track starts, and the pictures arrive some unknown time later. The deck is then told a
/// new record is on before there is anything to dress it in. The record lifts, comes down wearing the previous
/// album's sleeve, and lifts again when its own sleeve arrives. That gives two flights, and the first is wrong.
/// The further away the collection, the wider the gap. A borrowed shelf is the worst case, and that is where a
/// photographed disc is most likely to be new.
///
/// So the album travels with its pictures. It is replaced only when all of them are ready, and there is no way
/// to hold half of one.
public struct PlayingRecord: @unchecked Sendable {
    /// Which record this is: an album's name, or a station's. **This is the identity.** The deck compares it,
    /// and the next track of an album is the same record.
    public let album: String

    /// The sleeve. It is the label on the record, and the colour the record is pressed in.
    public let art: CoverArt?

    /// The photographed record itself, if the store has one.
    public let disc: ScannedDisc?

    public init(album: String, art: CoverArt?, disc: ScannedDisc?) {
        self.album = album
        self.art = art
        self.disc = disc
    }

    /// A record with no pictures at all: a station, or a track whose album the store has nothing for. It is
    /// still a record, and the deck shows the house pressing.
    public static func bare(_ album: String) -> PlayingRecord {
        PlayingRecord(album: album, art: nil, disc: nil)
    }
}
