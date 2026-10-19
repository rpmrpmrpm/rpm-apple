import SwiftUI
import RPMRadio
import RPMKit

/// The tuning dial: a printed card behind lit glass with a needle crossing it, like the scale of
/// a valve radio.
///
/// The desktop app has the same dial in `RPM.Desktop/.../RadioDial.cs`. Stations are set out
/// from left to right. Each one is printed flat as its three- or four-letter call sign followed
/// by a solid square, and the entries are stacked into as many rows as the card needs. The square
/// is the station's place on the band, and the needle tunes onto it. Dragging tunes. On release
/// the needle settles on the nearest station and does not stop between two, because that is how
/// a dial with detents works.
///
/// **The card is a card, not a viewport.** It can be longer than the glass and slide under it,
/// and the needle sits at the station's real place on it. The card is never re-centred on the
/// tuned station: a dial where every station appears in the middle of the band loses the one
/// thing that a printed scale shows. The card winds along only when the needle would otherwise
/// be off the glass.
///
/// The arithmetic is in ``DialCard``, where it can be tested. This view draws it.
public struct RadioDial: View {
    private let stations: [RadioStation]
    private let tuned: String?
    private let announced: String
    private let onTune: (RadioStation) -> Void

    public init(stations: [RadioStation], tuned: String?, announced: String,
                onTune: @escaping (RadioStation) -> Void) {
        self.stations = stations
        self.tuned = tuned
        self.announced = announced
        self.onTune = onTune
    }

    public static let height: CGFloat = 176
    private static let readoutBottom: CGFloat = 54

    private static let cyan = Color(red: 0x04 / 255, green: 0xC8 / 255, blue: 1)
    private static let scaleInk = Color(red: 0xC8 / 255, green: 0xEE / 255, blue: 1)
    private static let labelInk = Color(red: 0xDD / 255, green: 0xF2 / 255, blue: 1)
    private static let markInk = Color(red: 0xA8 / 255, green: 0xD4 / 255, blue: 0xEE / 255)

    /// Where the needle is, as a station. It is held as state and not derived, so a drag can
    /// move it without tuning on every point of travel.
    @State private var at: Int = 0

    /// How far the card has been wound. It is negative: the card slides left under the glass.
    @State private var wound: Double = 0

    @State private var glass: CGFloat = 0

    private var card: DialCard {
        DialCard.of(captions: stations.map { StationSign.of($0.display) },
                    glass: glass > 0 ? glass : 350,
                    height: Self.height, readoutBottom: Self.readoutBottom)
    }

    public var body: some View {
        let card = self.card

        return ZStack(alignment: .topLeading) {
            // The dial glass: a dark pane lit from behind, brighter along the scale line where
            // the lamp sits. Three stops and not a flat fill, so it does not look like another
            // card.
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0, green: 0x14 / 255, blue: 0x22 / 255)
                            .opacity(0x38 / 255), location: 0),
                    .init(color: Color(red: 0x04 / 255, green: 0x50 / 255, blue: 0x70 / 255)
                            .opacity(0x30 / 255), location: 0.55),
                    .init(color: Color(red: 0, green: 0x0A / 255, blue: 0x14 / 255)
                            .opacity(0x44 / 255), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)

            printed(card)

            readout
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(RPMInk.white(0x22 / 255), lineWidth: 1)
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { glass = geometry.size.width }
                    .onChange(of: geometry.size.width) { glass = $1 }
            }
        }
        .contentShape(Rectangle())
        .gesture(tuning(card))
        // A different list is a different card: start at its left edge and not at wherever the
        // last card was wound to.
        .onChange(of: stations.map(\.uuid)) { wound = 0; follow() }
        .onChange(of: tuned) { follow() }
        .onAppear { follow() }
    }

    // ── the lit panel ──

    private var readout: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(under?.display ?? Loc.get("Rpm_Radio_DialEmpty"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RPMInk.white(0xF2 / 255))
                    .lineLimit(1)

                Text(line)
                    .font(.system(size: 11.5))
                    .foregroundStyle(RPMInk.white(0x99 / 255))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // The station's own call sign, in the corner of the glass where a radio's maker
            // would put its badge. The desktop draws the logo here. A picture that has to be
            // fetched may not load, and it would leave an empty space on most rows. The call
            // sign is what the card is printed in anyway.
            if let under {
                Text(StationSign.of(under.display))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Self.cyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        let badge = RoundedRectangle(cornerRadius: 5, style: .continuous)
                        badge.fill(Color.black.opacity(0x26 / 255))
                            .overlay { badge.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(height: Self.readoutBottom, alignment: .top)
    }

    private var under: RadioStation? {
        stations.indices.contains(at) ? stations[at] : nil
    }

    /// The line under the name: what the station is announcing while it is the one playing, and
    /// what the station is otherwise.
    private var line: String {
        guard let under else { return "" }
        if under.uuid == tuned, !announced.isEmpty { return IcyTitle.line(announced) }

        return [RadioCountries.short(under.country, under.countryCode), under.quality]
            .filter { !$0.isEmpty }
            .joined(separator: "  \u{b7}  ")
    }

    // ── the card, and the needle over it ──

    private func printed(_ card: DialCard) -> some View {
        Canvas { context, size in
            let slid = CGAffineTransform(translationX: wound, y: 0)

            for x in card.ticks {
                context.fill(
                    Path(CGRect(x: x - 0.5, y: card.scaleTop, width: 1, height: DialCard.scaleSpan)
                        .applying(slid)),
                    with: .color(Self.scaleInk.opacity(0.55)))
            }

            for mark in card.printed {
                let rowTop = card.namesTop + Double(mark.row) * DialCard.nameLine
                let lit = mark.station == at

                context.fill(
                    Path(CGRect(x: mark.markX - DialCard.squareSize / 2,
                                y: rowTop + (DialCard.nameLine - DialCard.squareSize) / 2,
                                width: DialCard.squareSize, height: DialCard.squareSize)
                        .applying(slid)),
                    with: .color(lit ? Self.cyan : Self.markInk.opacity(0.8)))

                var caption = context.resolve(
                    Text(mark.caption)
                        .font(.system(size: DialCard.nameSize, weight: .medium))
                        .foregroundColor(lit ? Self.cyan : Self.labelInk.opacity(0.85)))
                caption.shading = .color(lit ? Self.cyan : Self.labelInk.opacity(0.85))

                context.draw(caption,
                             at: CGPoint(x: mark.nameLeft + mark.width + wound, y: rowTop),
                             anchor: .topTrailing)
            }

            needle(context, card, size)
        }
        .allowsHitTesting(false)
    }

    /// A hairline down the whole card, like a radio's pointer that crosses every band at once
    /// (not a short mark beside the graduations). A wider, dimmer copy behind it stands in for
    /// the lamp's glow, and a chevron at the top makes it point and not only mark.
    private func needle(_ context: GraphicsContext, _ card: DialCard, _ size: CGSize) {
        guard !stations.isEmpty else { return }

        let x = card.markOf(at, of: stations.count) + wound
        let top = card.namesTop - 3
        let height = card.scaleBottom - top + 2

        context.fill(
            Path(roundedRect: CGRect(x: x - 4.5, y: top - 2, width: 9, height: height + 4),
                 cornerRadius: 4),
            with: .color(Self.cyan.opacity(0x33 / 255)))

        context.fill(
            Path(roundedRect: CGRect(x: x - 1, y: top, width: 2, height: height), cornerRadius: 1),
            with: .color(Self.cyan))

        var chevron = Path()
        chevron.move(to: CGPoint(x: x - 5, y: top - DialCard.pointerRise))
        chevron.addLine(to: CGPoint(x: x, y: top - DialCard.pointerRise + 7))
        chevron.addLine(to: CGPoint(x: x + 5, y: top - DialCard.pointerRise))

        context.stroke(chevron, with: .color(Self.cyan),
                       style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    // ── tuning ──

    private func tuning(_ card: DialCard) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                // **A drag moves the needle, not the card.** The card is a printed scale: it
                // stays where it is and the pointer travels across it, which is what makes a
                // dial a dial. The card winds only when the needle would otherwise be off the
                // glass.
                guard let found = card.nearest(to: drag.location.x - wound,
                                               of: stations.count) else { return }

                // A dial with detents clicks as the needle passes each station, and this is the
                // only channel that can show that: the finger is over the card.
                if found != at { Haptics.tick() }

                at = found
                reveal(found, on: card)
            }
            .onEnded { _ in
                guard let station = under else { return }
                Haptics.commit()
                onTune(station)
            }
    }

    /// Points the needle at whatever is playing, for a station tuned from the list and not from
    /// the dial.
    private func follow() {
        guard let tuned, let found = stations.firstIndex(where: { $0.uuid == tuned })
        else { return }

        at = found
        reveal(found, on: card)
    }

    /// Winds the card along, but only when the needle would be too near an edge to be read. The
    /// card is never re-centred on the tuned station: a dial where every station appears in the
    /// middle of the band loses the one thing that a printed scale shows.
    private func reveal(_ station: Int, on card: DialCard) {
        guard glass > 0, card.scaleWidth > glass else { return }

        let mark = card.markOf(station, of: stations.count)
        let x = mark + wound

        // How close to the glass edge the needle may be before the card is wound.
        let margin: Double = 56
        guard x < margin || x > glass - margin else { return }

        wound = card.slide(bringing: mark, to: x < margin ? margin : glass - margin,
                           glass: glass)
    }
}
