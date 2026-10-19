import Foundation

/// The layout of the printed labels on a tuning dial's card.
///
/// This is the arithmetic behind `RPM.Desktop/.../RadioDial.cs`, moved out of the drawing code.
/// The card is not a fixed template. How long it must be, how many rows of call signs it needs,
/// which signs clear their neighbours and where each mark lands all depend on the stations shown
/// and the live width of the glass. **None of that can be checked by looking at the screen**, so
/// the layout is kept here, in code that can be tested.
public struct DialCard: Equatable, Sendable {
    // ── how a card is printed ──

    /// The height of one row of call signs, from baseline to baseline.
    public static let nameLine: Double = 11

    /// The clear space between two call signs on the same row.
    public static let nameGap: Double = 7

    /// The square marks the station's exact place on the band. The needle tunes onto it.
    /// It is as tall as the capitals of the sign, so the two read as one mark.
    public static let squareSize: Double = 6.5
    public static let squareGap: Double = 4

    /// The space a sign must keep clear on its row, beyond its own width.
    public static let squareSlot = squareGap + squareSize

    /// How tall the graduations are, and how far the needle's chevron stands above them.
    public static let scaleSpan: Double = 16
    public static let pointerRise: Double = 13

    /// The most rows of call signs a card prints, however tall the card gets. More than six
    /// rows stops looking like a dial and starts looking like a table of contents.
    public static let mostRows = 6

    /// The estimated width of one character at the printed size. The width is estimated, not
    /// measured. Measuring every string would need a text pass for each station on the card.
    ///
    /// The estimate is deliberately generous. It sets the width each sign is given. If it is too
    /// low, the last letter of a long sign is clipped. If it is too high, neighbours have a little
    /// more air between them, which a dial card can afford.
    public static let nameSize: Double = 9
    public static let charWidth = nameSize * 0.7

    /// The most glass widths of scale the card prints before it starts leaving call signs out.
    ///
    /// The card is wider than the glass and slides under it, so a crowded list keeps every sign
    /// instead of dropping most of them. The width is still capped. Without a cap, a search with a
    /// thousand stations would lay out a thousand signs across seventeen thousand points to show
    /// twenty of them. Past this cap, signs are left out. A card that the reader cannot drag to
    /// its end is no more useful than a sparse one.
    public static let mostScreens: Double = 6

    /// The margin on the right. The needle never reaches the glass edge inside this margin.
    public static let edge: Double = 16

    // ── what one printed station is ──

    public struct Printed: Equatable, Sendable {
        public let station: Int
        public let row: Int
        public let caption: String

        /// Where the square sits on the CARD. This is not where it sits on the glass once the
        /// card is longer than the glass.
        public let markX: Double

        public let nameLeft: Double
        public let width: Double
    }

    /// The width of the printed card. It equals the glass width until the call signs need more
    /// room. After that it is wider, and the card can slide.
    public let scaleWidth: Double

    /// Where the graduations are, on the card.
    public let ticks: [Double]

    /// The stations that get a printed sign. A station that cannot clear its neighbours on any
    /// row keeps its graduation but gets no caption. That is better than printing it over the
    /// sign beside it.
    public let printed: [Printed]

    public let nameRows: Int

    /// Where the block sits vertically. The instrument is the needle head, the rows of signs and
    /// the graduations under them. It is centred as one block in the space below the readout.
    /// It is not pinned to a fixed top, which would leave the lower half of the dial empty.
    public let namesTop: Double
    public let scaleTop: Double
    public let scaleBottom: Double

    /// How far in the first mark sits.
    ///
    /// **This is wider than the right margin, and it has to be.** A sign is printed to the LEFT
    /// of its own square. If the first station sat at the normal margin of sixteen points, its
    /// sign would print off the left end of the card, where there is nothing to scroll to. The
    /// first station gets room for the widest sign.
    public let leftEdge: Double

    /// Lays out a card.
    ///
    /// - Parameters:
    ///   - captions: one call sign per station, in the order they are listed.
    ///   - glass: how wide the lit pane is.
    ///   - height: how tall the whole dial is.
    ///   - readoutBottom: the foot of the lit panel. The card lives below it.
    public static func of(captions: [String], glass: Double,
                          height: Double = 176, readoutBottom: Double = 54) -> DialCard {
        let count = captions.count

        // The number of rows is worked out from the room that is actually there, not from a fixed
        // number. The card is centred in the space the readout leaves, so the row count follows
        // the height of the control.
        let room = max(0, height - 8 - readoutBottom)
        let maxRows = min(max(Int((room - pointerRise - scaleSpan) / nameLine), 1), mostRows)

        let widths = captions.map { max(8, Double($0.count) * charWidth) }

        // The length the card needs. A sign printed flat takes its own width plus a gap. Stacked
        // into rows, the card needs only a fraction of that total. The length is worked out from
        // the total ink, not from a fixed pitch. So a card of six short names fits the glass, and
        // a card of a hundred long names grows, with no hand tuning.
        let ink = widths.reduce(0) { $0 + $1 + squareSlot + nameGap }
        let wanted = ink / Double(maxRows) + 32
        let scaleWidth = min(max(wanted, glass), max(glass, glass * mostScreens))

        let widest = widths.max() ?? 0
        let leftEdge = max(edge, widest + squareGap + squareSize / 2)

        let inset = max(1, scaleWidth - leftEdge - edge)
        func at(_ fraction: Double) -> Double { leftEdge + min(max(fraction, 0), 1) * inset }
        func fraction(_ i: Int) -> Double { count <= 0 ? 0.5 : (Double(i) + 0.5) / Double(count) }

        // A card too crowded for one graduation per station gets evenly spaced graduations.
        // It gets no captions at all.
        let pitch = count > 0 ? inset / Double(count) : 0
        let perStation = count > 0 && pitch >= 4

        var ticks: [Double] = []
        if perStation {
            ticks = (0..<count).map { at(fraction($0)) }
        } else {
            let howMany = max(8, Int(inset / 11))
            ticks = (0..<howMany).map { at((Double($0) + 0.5) / Double(howMany)) }
        }

        // Lay the entries out in rows, left to right. An entry is its sign and the square after
        // it. **The square sits ON the station's position**, so the sign reaches back to the left
        // of it. Each entry goes on the topmost row whose last entry it clears.
        var printed: [Printed] = []
        var nameRows = 0

        if perStation {
            var rowEnd = [Double](repeating: -.infinity, count: maxRows)

            for i in 0..<count {
                let mark = at(fraction(i))
                let left = mark - squareSize / 2 - squareGap - widths[i]

                for row in 0..<maxRows where left >= rowEnd[row] {
                    rowEnd[row] = mark + squareSize / 2 + nameGap
                    printed.append(Printed(station: i, row: row, caption: captions[i],
                                           markX: mark, nameLeft: left, width: widths[i]))
                    nameRows = max(nameRows, row + 1)
                    break
                }
            }
        }

        let names = Double(nameRows) * nameLine
        let block = pointerRise + names + scaleSpan
        let top = readoutBottom + max(0, (room - block) / 2) + pointerRise

        return DialCard(scaleWidth: scaleWidth, ticks: ticks, printed: printed,
                        nameRows: nameRows, namesTop: top,
                        scaleTop: top + names, scaleBottom: top + names + scaleSpan,
                        leftEdge: leftEdge)
    }

    /// Where a station's mark sits on the card.
    public func markOf(_ station: Int, of count: Int) -> Double {
        let fraction = count <= 0 ? 0.5 : (Double(station) + 0.5) / Double(count)
        return leftEdge + min(max(fraction, 0), 1) * span
    }

    private var span: Double { max(1, scaleWidth - leftEdge - Self.edge) }

    /// The station nearest to a point on the CARD. A released dial snaps to this station. That
    /// is what a detented dial does: it settles on a station rather than stopping between two.
    public func nearest(to cardX: Double, of count: Int) -> Int? {
        guard count > 0 else { return nil }

        let fraction = min(max((cardX - leftEdge) / span, 0), 1)
        return min(max(Int(fraction * Double(count)), 0), count - 1)
    }

    /// How far the card must slide so the point at `cardX` sits at `glassX`. The slide stops at
    /// what the card can travel. **The clamp stops the card being dragged past its own ends,
    /// which would leave blank glass.**
    public func slide(bringing cardX: Double, to glassX: Double, glass: Double) -> Double {
        min(max(glassX - cardX, -max(0, scaleWidth - glass)), 0)
    }
}
