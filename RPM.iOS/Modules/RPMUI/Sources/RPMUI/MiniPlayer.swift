import SwiftUI
import RPMSharedUI
import RPMKit
import RPMAudio
import RPMArt
import RPMDesign
import RPMRadio

/// Shows what is playing, above the tab bar, on every screen except the player itself.
///
/// It has no background, corners or margins of its own: `RPMChrome` puts it on a floating
/// glass card above the tab capsule.
///
/// The progress bar under the row is deliberately not a seek bar. Scrubbing needs a taller
/// touch target, and the player, one tap away, has one.
public struct MiniPlayer: View {
    private let player: Player
    private let art: CoverArt?
    private let onOpen: () -> Void

    public init(player: Player, art: CoverArt?, onOpen: @escaping () -> Void = {}) {
        self.player = player
        self.art = art
        self.onOpen = onOpen
    }

    /// Whether the strip has anything to show. A station belongs on it for the same reason
    /// as a track: **the strip lets the user pause without leaving the screen.**
    public static func hasSomethingToSay(_ player: Player) -> Bool {
        player.current != nil || player.station != nil
    }

    public var body: some View {
        if Self.hasSomethingToSay(player) {
            VStack(spacing: Self.barGap) {
                // **15 points on the left, 9 on the right.** The capsule that `RPMChrome`
                // puts this on curves at half the strip's height, and the corners of the
                // sleeve must stay 7 points inside that curve. The keys' glyphs are narrower
                // than their frames, so the right end needs only 9.
                row
                    .padding(.leading, Self.sleeveInset)
                    .padding(.trailing, 9)

                // The bar sits on the bottom border of the card, with nothing under it. Its
                // ends stop where the border stops running straight.
                //
                // It uses the sleeve's accent colour, the one the wall, the drawers and the
                // pressed vinyl are painted from, and white when the record has no colour.
                // `GlassInk` stops a dark accent from drawing a line that cannot be seen.
                MiniProgress(player: player,
                             ink: art?.accent.map { GlassInk($0.base) } ?? .white)
                    .frame(height: Self.bar)
                    .padding(.horizontal, Self.barInset)
            }
            // 9 points above the 40-point sleeve and keys. The rest of the 62-point strip is
            // the gap down to the bar.
            .padding(.top, Self.aboveRow)
            .frame(height: Self.strip)
            // A tap on the strip opens the player, except a tap on a key. Any tap that is
            // not on a key opens the player.
            .contentShape(Capsule())
            .onTapGesture(perform: onOpen)
        }
    }

    /// The strip's height: the row, the bar under it, and the space around both.
    private static let strip: CGFloat = 62

    /// The height of the row of sleeve and keys, and the space above it.
    private static let rowHeight: CGFloat = 40
    private static let aboveRow: CGFloat = 9

    /// The progress bar's thickness.
    private static let bar: CGFloat = 2

    /// The distance from the side of the strip to the sleeve's left edge.
    private static let sleeveInset: CGFloat = 15

    /// The distance from each side of the strip to the nearest end of the bar. `RPMChrome`
    /// draws the strip on a capsule. Its bottom border is straight between the two curves,
    /// which start half the strip's height in from each side. The bar covers only that
    /// straight part.
    private static let barInset: CGFloat = strip / 2

    /// The gap between the row and the bar: the height that is left in the strip, because
    /// nothing is under the bar.
    private static let barGap: CGFloat = strip - aboveRow - rowHeight - bar

    /// The sleeve, the two lines of text and the keys.
    private var row: some View {
        HStack(spacing: 10) {
            sleeve

            // Each line scrolls through once if it does not fit. See `OnceTicker`.
            VStack(alignment: .leading, spacing: 1) {
                OnceTicker(title, font: RPMFont.display(14), ink: .white)

                // When a record stops because there is no network, the reason replaces
                // the artist, because this strip is what the user sees at that moment.
                OnceTicker(player.failure == .offline ? (player.trouble ?? said) : said,
                           font: RPMFont.display(11), ink: RPMInk.white(0x88 / 255))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Previous, play and next. There is no stop key: on a strip this small it
            // would be easy to hit by accident, and stopping the music is never urgent.
            //
            // **The two outer keys are disabled on a station.** A station has no queue,
            // so there is nothing to step to.
            HStack(spacing: 0) {
                key(Glyph.backward) { Task { await player.previous() } }
                    .accessibilityLabel(Loc.get("Transport_Previous"))
                    .opacity(player.onTheRadio ? 0.3 : 1)
                    .disabled(player.onTheRadio)

                // The key shows what the user asked for, not the actual audio state. It
                // shows a pause key during the second a track takes to open, and a ring
                // around it if that takes several seconds. See `BusyKey`.
                BusyKey(busy: player.isBusy, ring: 16) {
                    key(player.wantsToPlay ? Glyph.pause : Glyph.play) { player.toggle() }
                        .accessibilityLabel(player.wantsToPlay ? Loc.get("CloudChip_Pause") : Loc.get("AlbumMenu_Play"))
                }

                key(Glyph.forward) { Task { await player.next() } }
                    .accessibilityLabel(Loc.get("Transport_Next"))
                    .opacity(player.hasNext ? 1 : 0.3)
                    .disabled(!player.hasNext)
            }
        }
        .frame(height: Self.rowHeight)
    }

    /// The song title that a station announced, otherwise the station's own name, or the
    /// track's title when a track is playing. A station that has announced nothing shows
    /// its own name, because a blank strip would look as if nothing is playing.
    private var title: String {
        guard let station = player.station else { return player.current?.title ?? "" }

        let (_, said) = IcyTitle.split(player.announced)
        return said ?? station.display
    }

    /// The artist that a station announced. If the station has announced nothing, it shows
    /// the station's country and quality instead. It never repeats the station's name,
    /// because the same words on both lines would waste a line.
    private var said: String {
        guard let station = player.station else { return player.current?.artist ?? "" }

        if let (artist, _) = Optional(IcyTitle.split(player.announced)), let artist {
            return artist
        }

        return [RadioCountries.short(station.country, station.countryCode), station.quality]
            .filter { !$0.isEmpty }
            .joined(separator: "  \u{b7}  ")
    }

    /// The same style as the wall and the player's cover tile: a faint background, the art
    /// over it, and the record glyph when there is no art.
    private var sleeve: some View {
        let edge: CGFloat = 40
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return ZStack {
            shape.fill(Color.black.opacity(0x22 / 255))
                .overlay { shape.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }

            if let art, player.station == nil {
                Sleeve(image: Image(decorative: art.image, scale: 1))
                    .frame(width: edge, height: edge)
                    .clipShape(shape)
            } else if let station = player.station {
                // The station's own logo is drawn where the sleeve would be, as on the
                // desktop. If the logo's published address no longer works, the station's
                // call sign is drawn instead.
                StationFace(station: station, edge: edge, inset: 3, onWearing: { _ in }) {
                    Text(StationSign.of(station.display))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(RPMInk.white(0xAA / 255))
                }
                // The background behind a transparent logo fills the sleeve, so it is
                // clipped to the shape and the edge is drawn again over it.
                .clipShape(shape)
                .overlay { shape.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
            } else {
                Text(Glyph.record)
                    .font(RPMFont.icon(16))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: edge, height: edge)
    }

    private func key(_ glyph: String, _ press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(glyph)
                .font(RPMFont.icon(15))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Shows how far through the track the player is: a line in `ink` from the left of the
/// frame it is given, with nothing drawn for the part that is not played yet.
///
/// The ink is a ``GlassInk`` and not a plain colour, so every colour passed in has already
/// been through the lightness check.
///
/// It is drawn here and does not use the system's linear `ProgressView`, which draws at its
/// own thickness whatever frame it is given. The band under the row is 2 points high.
///
/// It is a separate view so that the position, which changes several times a second, is
/// read only here, and a tick redraws the bar and not the whole strip. ``PlayerNeedle`` is
/// built this way for the same reason. Nothing is drawn for a station, which has no length,
/// but the band keeps its height, so the row does not move when a station replaces a track.
private struct MiniProgress: View {
    let player: Player
    let ink: GlassInk

    var body: some View {
        // The `GeometryReader` stays for a station too, with nothing inside it. An empty body
        // takes no space even with a frame on it, so without the reader the strip would lose
        // the bar and the gap above it, and the row would sit 6.5 points lower than for a track.
        GeometryReader { box in
            if player.station == nil {
                let played = box.size.width * through

                // Only the played part is drawn. Nothing is drawn behind the rest, because
                // the bar sits on the card's bottom border, the line it grows along.
                //
                // It looks like light inside the glass, not a line on top of it. It fades
                // in from transparent over its first `fade` points, so its left end joins
                // the border smoothly. It is slightly transparent so the border shows
                // through, and its colour spills into the glass around it.
                Capsule()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: ink.color.opacity(0), location: 0),
                            .init(color: ink.color.opacity(Self.lit),
                                  location: min(0.5, Self.fade / max(played, 1))),
                            .init(color: ink.color.opacity(Self.lit), location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: played, alignment: .leading)
                    .shadow(color: ink.color.opacity(Self.spill), radius: 3)
            }
        }
    }

    /// The opacity of the line, the length in points over which its left end fades in, and
    /// the opacity of the shadow that spills its colour into the glass around it.
    private static let lit = 0.92
    private static let fade: CGFloat = 16
    private static let spill = 0.55

    /// From 0 to 1. It is 0 while a track is still opening and its length is not known.
    private var through: Double {
        guard player.duration > .zero else { return 0 }
        return min(1, max(0, player.position.seconds / player.duration.seconds))
    }
}
