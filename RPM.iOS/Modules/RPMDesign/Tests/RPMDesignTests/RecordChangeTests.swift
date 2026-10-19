import Testing
import CoreGraphics
@testable import RPMDesign

/// The one rule: a record's face only changes where nobody can see it change.
///
/// This matches the desktop's `RecordFaceTests`. `RecordChange` holds no pictures, so the
/// arrivals can be sent in any order and the rule is checked directly.

private func face(_ album: String, hue: RGB? = RGB(1, 2, 3),
                  label: CGImage? = nil, cd: ScannedDisc? = nil) -> RecordFace {
    RecordFace(album: album, hue: hue, label: label, cd: cd)
}

/// A one-pixel picture. What it shows does not matter here. Only whether there is a picture does.
private func picture() -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

// ── the rule ──

/// The whole rule: a different record on a live deck lifts first. It dresses only once it is off
/// the deck.
@Test func aRecordChangesItsFaceOnlyWhileItIsOffTheDeck() {
    var deck = RecordChange(onDeck: true)

    let lift = deck.wear(face("Hex"))
    #expect(lift == Move(dress: false, fly: .lift))
    #expect(deck.deck == .on)

    deck.flying(.lift)
    #expect(deck.deck == .lifting)

    let off = deck.landed()
    #expect(off == Move(dress: true, fly: .drop))
    #expect(deck.deck == .off)
}

/// Nothing is decided while the disc is in the air. A record that arrives then is remembered and
/// handled when it lands.
@Test func nothingIsDecidedWhileTheRecordIsInTheAir() {
    var deck = RecordChange(onDeck: true)
    _ = deck.wear(face("Hex"))
    deck.flying(.lift)

    #expect(deck.wear(face("Spirit of Eden")) == .nothing)
    #expect(deck.landed() == Move(dress: true, fly: .drop))

    // The face is the last one asked for, not the first.
    #expect(deck.wanted.album == "Spirit of Eden")
}

/// The next track of an album is the same record. Each track brings a freshly decoded copy of the
/// same sleeve. Taking the disc off to put the same picture back on would be a record change that
/// nobody asked for.
@Test func anotherTrackOfTheSameRecordIsNotARecordChange() {
    var deck = RecordChange(onDeck: false)

    _ = deck.wear(face("Hex", label: picture()))
    deck.flying(.drop)
    _ = deck.landed()
    deck.dressed()
    #expect(deck.deck == .on)

    // Same album, same colour, another decode of the same sleeve.
    #expect(deck.wear(face("Hex", label: picture())) == .nothing)
}

/// Case does not decide which record this is.
@Test func theSameNameInAnotherCaseIsTheSameRecord() {
    var deck = RecordChange(onDeck: false)
    _ = deck.wear(face("Hex"))
    deck.flying(.drop)
    _ = deck.landed()
    deck.dressed()

    #expect(deck.wear(face("HEX")) == .nothing)
}

/// A CD that arrives after the record is down is a change. Otherwise the album plays on the drawn
/// disc while its own photographed disc sits in hand.
@Test func aCdArrivingAfterTheRecordIsDownIsAChange() {
    var deck = RecordChange(onDeck: false)
    _ = deck.wear(face("Hex"))
    deck.flying(.drop)
    _ = deck.landed()
    deck.dressed()

    #expect(deck.wear(face("Hex", cd: ScannedDisc(picture()))) == Move(dress: false, fly: .lift))
}

/// The sleeve arrives on its own timing too, so the same applies to it.
@Test func aSleeveArrivingAfterTheRecordIsDownIsAChange() {
    var deck = RecordChange(onDeck: false)
    _ = deck.wear(face("Hex"))
    deck.flying(.drop)
    _ = deck.landed()
    deck.dressed()

    #expect(deck.wear(face("Hex", label: picture())) == Move(dress: false, fly: .lift))
}

/// A colour is part of the face. The same album in another colour is a different record, and it
/// must come off the deck like any other.
@Test func aDifferentPressingOfTheSameAlbumIsStillAChange() {
    var deck = RecordChange(onDeck: false)
    _ = deck.wear(face("Hex", hue: RGB(1, 2, 3)))
    deck.flying(.drop)
    _ = deck.landed()
    deck.dressed()

    #expect(deck.wear(face("Hex", hue: RGB(9, 9, 9))) == Move(dress: false, fly: .lift))
}

/// An empty deck drops as soon as it is told what to wear, and dresses on the way. It is already
/// a place where the face may change.
@Test func anEmptyDeckDressesAndDropsInOneAnswer() {
    var deck = RecordChange(onDeck: false)

    #expect(deck.wear(face("Hex")) == Move(dress: true, fly: .drop))
}

/// The disc is on the deck with the right record. Nothing needs to happen, however many times it
/// is asked.
@Test func aRecordThatIsAlreadyOnStaysWhereItIs() {
    var deck = RecordChange(onDeck: false)
    _ = deck.wear(face("Hex"))
    deck.flying(.drop)
    _ = deck.landed()
    deck.dressed()

    #expect(deck.landed() == .nothing)
    #expect(deck.wear(face("Hex")) == .nothing)
}

// ── what kind of picture of a record this is ──

/// A picture the size of the whole disc, with only its middle third filled in. This is what the
/// desktop's `DiscStamp` cuts out of a photo of a vinyl label.
private func labelScan(edge: Int = 400) -> CGImage {
    disc(edge: edge, fill: 1.0 / 3.0)
}

/// The same square, filled edge to edge. This is a photographed CD, or a whole vinyl side.
private func cdScan(edge: Int = 400) -> CGImage {
    disc(edge: edge, fill: 1)
}

private func disc(edge: Int, fill: Double) -> CGImage {
    let context = CGContext(
        data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    context.clear(CGRect(x: 0, y: 0, width: edge, height: edge))
    context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))

    let side = Double(edge) * fill
    let inset = (Double(edge) - side) / 2
    context.fillEllipse(in: CGRect(x: inset, y: inset, width: side, height: side))

    return context.makeImage()!
}

/// **The rule the whole thing depends on.** A CD scan is the record, and it hides the pressing.
/// A label scan is worn on the record, which keeps turning under it. Read the wrong way, a label
/// scan leaves a small picture floating where the record was.
@Test func aWholeDiscCoversTheRecordAndALabelDoesNot() {
    #expect(ScannedDisc(cdScan()).coversRecord)
    #expect(!ScannedDisc(labelScan()).coversRecord)
}

/// A picture with no transparency cannot be a label stamp, because nothing was cut out of it. It
/// is an ordinary photo of a disc on a table, so it counts as the whole record.
@Test func aFlatPictureIsTheWholeRecord() {
    let edge = 200
    let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))

    #expect(ScannedDisc(context.makeImage()!).coversRecord)
}

/// A picture too small to test is taken as the whole record. This is the default for a picture
/// that is too small to read.
@Test func aPictureTooSmallToReadIsTheWholeRecord() {
    #expect(ScannedDisc(labelScan(edge: 8)).coversRecord)
}

/// Changing a label scan to a whole-disc scan changes how the deck looks. The pressing appears or
/// disappears under the label. So it counts as a change of record, not as a picture swapped on a
/// disc that is still turning.
@Test func aLabelAndAWholeDiscAreDifferentRecords() {
    let asLabel = face("Hex", cd: ScannedDisc(labelScan()))
    let asCd = face("Hex", cd: ScannedDisc(cdScan()))

    #expect(!asLabel.isSameRecord(as: asCd))

    // Two decodes of the same kind are still the same record. Every track brings a fresh copy,
    // and comparing the pictures would take the disc off for each track.
    #expect(asLabel.isSameRecord(as: face("Hex", cd: ScannedDisc(labelScan()))))
}

// ── how the face is published ──

/// Sends a record change all the way through, the way `StageView` does. Returns how many trips
/// off the deck it took. A trip is what a listener sees: the record shrinking into the corner
/// and coming back.
private func flights(of faces: [RecordFace]) -> Int {
    var deck = RecordChange(onDeck: true)
    var trips = 0

    func carry(_ move: Move) {
        if move.dress { deck.dressed() }
        guard move.fly != .stay else { return }

        if move.fly == .lift { trips += 1 }
        deck.flying(move.fly)
        carry(deck.landed())
    }

    // The deck starts holding the first record, as it does once the first album of a session is
    // playing. Every record after that is a change.
    carry(deck.wear(faces[0]))
    trips = 0

    for face in faces.dropFirst() { carry(deck.wear(face)) }
    return trips
}

/// **Why the album travels with its pictures.** A track's album name is known as soon as the track
/// starts. Its pictures are not. Publishing them separately says "new record" twice: first with the
/// last album's face still in hand, then again when the real face arrives. The listener sees the
/// record fly off, come down wearing the wrong sleeve, and fly off again.
///
/// This is the fault `PlayingRecord` prevents, written as two sequences.
@Test func aFaceArrivingInPiecesChangesTheRecordTwice() {
    let first = face("Spirit of Eden", hue: RGB(1, 2, 3), label: picture())

    // Each field is published separately: first the new album name, still with the old sleeve and
    // colour. Then the new sleeve arrives.
    let inPieces = [
        first,
        face("Laughing Stock", hue: RGB(1, 2, 3), label: picture()),
        face("Laughing Stock", hue: RGB(9, 9, 9), label: picture()),
    ]

    #expect(flights(of: inPieces) == 2)
}

/// Published as one value, the same album change is one trip. The record is already wearing its
/// own face when it comes down.
@Test func aFaceArrivingWholeChangesTheRecordOnce() {
    let first = face("Spirit of Eden", hue: RGB(1, 2, 3), label: picture())
    let next = face("Laughing Stock", hue: RGB(9, 9, 9), label: picture())

    #expect(flights(of: [first, next]) == 1)
}

/// The disc is the part of the face most likely to arrive late. It is a second object in the
/// store, and it may be fetched over the network. Held back until it is in hand, it costs nothing.
/// Published when it arrives, it adds a whole extra trip off the deck for a record that was already
/// down.
@Test func aDiscArrivingAfterItsSleeveIsAWholeExtraFlight() {
    let first = face("Spirit of Eden", hue: RGB(1, 2, 3), label: picture())
    let sleeveOnly = face("Laughing Stock", hue: RGB(9, 9, 9), label: picture())
    let whole = face("Laughing Stock", hue: RGB(9, 9, 9), label: picture(),
                     cd: ScannedDisc(cdScan()))

    #expect(flights(of: [first, sleeveOnly, whole]) == 2)
    #expect(flights(of: [first, whole]) == 1)
}

/// The next track of a record is the same record, whatever else it brings. This stops a
/// fourteen-track album from being fourteen record changes.
@Test func anotherTrackOfOneRecordIsNoFlightAtAll() {
    let album = { face("Laughing Stock", hue: RGB(9, 9, 9), label: picture()) }

    #expect(flights(of: [album(), album(), album(), album()]) == 0)
}
