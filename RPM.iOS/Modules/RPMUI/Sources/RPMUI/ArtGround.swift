import SwiftUI
import RPMDesign

/// The ground a page stands on when it has a picture of its own: the record underneath,
/// that picture blurred out of being a picture, and the veil the words are read through.
///
/// This matches `PageBackdrop` and the `Lend` a detail page makes on the desktop, where a
/// page hands its own ground to the whole window, so the app takes the colours of what
/// is being read instead of its own wallpaper. There is no window to lend to here: a
/// `NavigationStack` paints over anything laid under the app, so every page carries its
/// own ground. The layers are the same as the desktop's.
///
/// **One view shared by all pages.** The record page, the artist page, one list
/// and the home screen all stand on this, and the blur radius, the tint and the veil are
/// the same for all four, so they cannot drift apart.
///
/// **A picture, never a live blur.** A backdrop blur behind a scrolling page is the one
/// thing this app must not ask for, and none of these pictures moves.
public struct ArtGround: View {
    /// What the page is showing, or nil while it is still being read. Then the
    /// record shows through, which is how every page opens.
    private let picture: Image?

    /// The colour read off that picture, laid over it at about a fifth (0.18) so a ground
    /// made from a grey sleeve still has the record's own colour cast. Nil is no tint, which
    /// is what a photograph of a person gets: the colour there is the photograph's.
    private let accent: Accent?

    /// The colours a page is lit in where it has no picture of its own. A generated list uses
    /// its own three, from top to foot: the colours its frame is inked from and its room
    /// drifts in. Empty means no colour layer, which is the case for every other page.
    ///
    /// The desktop's ground has the same layer: a flat colour read off a sleeve, or the
    /// gradient an artist's box is painted in. See `PageBackdrop.Ground.Colour`.
    private let colours: [Color]

    /// What the picture is OF, so that a page moving from one picture to another
    /// dissolves between them instead of switching at once. The home screen's banner needs
    /// it: the ground follows the card in front, and the card in front moves under a
    /// finger.
    ///
    /// **The ground changes only when this does.** A new picture under the same name is not
    /// drawn, so a caller whose picture can change for one subject names the picture as well:
    /// see ``BannerDress/wearing``.
    private let showing: String

    /// How long the ground takes to change from one picture to another.
    ///
    /// **Set by the caller**, because only the caller knows what the change belongs to. A
    /// record page opens on its own picture and has nothing to keep in step with. On the home
    /// screen the ground changes because a card is moving across, so it must last as long as
    /// that movement.
    private let dissolve: Double

    public init(picture: Image?, accent: Accent? = nil, showing: String = "",
                colours: [Color] = [], dissolve: Double = 0.25) {
        self.picture = picture
        self.accent = accent
        self.showing = showing
        self.colours = colours
        self.dissolve = dissolve
    }

    /// What is on screen, as one value: nothing until a picture lands, and then which picture.
    private var standing: String { picture == nil ? "" : showing }

    /// The ground that is being replaced, held while the new one comes in over it.
    ///
    /// **Why the outgoing one is kept and not faded out.** If one picture fades out while the
    /// other fades in, both are half visible in the middle, and the app's own ground shows
    /// through the pair. The screen then dips and comes back, which looks like a flash and not
    /// like one picture becoming another. The leaving picture therefore stays at full
    /// strength until the arriving one has covered it.
    @State private var under: Worn?

    /// What is coming in over it, and how far in it has come.
    @State private var over: Worn?
    @State private var covered: Double = 1

    /// One ground: a picture, the colour read off it, and what it is of.
    private struct Worn: Equatable {
        let of: String
        let picture: Image?
        let accent: Accent?
    }

    private var worn: Worn { Worn(of: standing, picture: picture, accent: accent) }

    public var body: some View {
        ZStack {
            // A page with no picture of its own falls through to the app's own ground,
            // the grooves, rather than to a flat field.
            VinylGround()

            // Under the picture, not instead of it: a page that has both is a picture standing on
            // its own colours, and one that has neither is the record showing through.
            if colours.count > 1 {
                LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom)
            }

            if let under { wash(under) }
            if let over { wash(over).opacity(covered) }

            // Heavier at the foot, where the listings are: the head of a page is a sleeve
            // or a photograph with a title on it and can stand on colour, and a list of
            // forty rows cannot.
            LinearGradient(
                stops: [.init(color: .black.opacity(0x59 / 255), location: 0),
                        .init(color: .black.opacity(0x8C / 255), location: 0.42),
                        .init(color: .black.opacity(0xBF / 255), location: 1)],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { over = worn }
        .onChange(of: standing) { _, _ in
            under = over
            over = worn
            covered = 0

            withAnimation(.easeInOut(duration: dissolve)) {
                covered = 1
            } completion: {
                // Only once it is actually covered. Dropped on a timer of its own, the one
                // underneath would go while the one over it was still half there.
                under = nil
            }
        }
    }

    @ViewBuilder
    private func wash(_ worn: Worn) -> some View {
        if let picture = worn.picture {
            // **Clipped, and inside a `Color.clear`.** A resizable image filling its
            // frame reports the SCALED size as its own, not the size it was offered.
            // A square sleeve over a tall page would make the page eight hundred points
            // wide, and everything centred in it would sit off the right of the screen.
            // The clip keeps the ground at the size of the page.
            Color.clear
                .overlay {
                    picture
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 60, opaque: true)
                }
                .clipped()
                .overlay(worn.accent?.base.color.opacity(0.18) ?? .clear)
        }
    }
}

// ── what a picture casts under itself ──

extension View {
    /// Keeps the top `above` points as they are and takes the `depth` points under them away to
    /// nothing.
    ///
    /// What turns a drawing that runs on past its own foot into a reflection. The fade is
    /// what makes it a reflection: a mirror at full strength all the way down looks like a
    /// second card, and one that starts at half strength draws a seam at the line where the
    /// two are the same picture.
    ///
    /// Defined once because two surfaces use it: the home strip's cards, and the room at the
    /// head of a list.
    func mirrorFade(above: Double, depth: Double) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.white.frame(height: max(0, above))

                // A smoothstep from full to nothing: flat where it leaves the drawing above and
                // flat where it reaches nothing, so neither end shows as a line.
                LinearGradient(
                    stops: [.init(color: .white, location: 0),
                            .init(color: .white.opacity(0.84), location: 0.25),
                            .init(color: .white.opacity(0.5), location: 0.5),
                            .init(color: .white.opacity(0.16), location: 0.75),
                            .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: max(0, depth))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

// ── a photograph blurred toward its foot and mirrored under it ──

/// What ``RunOff`` turns over under the card.
enum RunOffReflection: Hashable, Sendable {
    /// The card as it is drawn: blurred where the card is blurred and sharp where it is sharp. The
    /// deeper the mirror runs, the higher up the card it reaches, so a deep one ends on the sharp
    /// part of the photograph.
    case asDrawn

    /// The card at the blur of its foot, all the way down, so no part of the photograph is sharp
    /// under the card. The foot is drawn at that blur too, so the two still match where they meet.
    ///
    /// The home banner's. Its mirror runs behind the quick selection, whose lines leave most of it
    /// showing, and a sharp end would look like a second photograph behind the list.
    case blurred
}

/// A picture drawn `plate` points tall, blurred toward its foot, and mirrored under itself
/// `depth` points deep.
///
/// The mirror is of the finished card, blur and washes included, turned over about the card's
/// foot. It matches the card row for row at the foot, so there is no line where the two meet.
///
/// Callers fade the mirror out themselves with ``SwiftUI/View/mirrorFade(above:depth:)``, so a
/// card can fade its room and its photograph with one mask.
///
/// `blurs` is false when there is no photograph: there is nothing to blur, and an opaque blur of
/// a translucent wash would cover whatever stands under it.
struct RunOff<Face: View>: View {
    let plate: Double
    let depth: Double
    let blurs: Bool

    /// Where the blur starts, as a fraction of the card's height from the top. Above it the
    /// picture is sharp. Each caller states it, because where the faces sit differs by screen.
    let blurFrom: Double

    /// What is turned over under the card. Each caller states it, because what stands over the
    /// mirror differs by screen.
    let reflection: RunOffReflection

    @ViewBuilder let face: () -> Face

    var body: some View {
        ZStack(alignment: .top) {
            mirrored

            // The card and its mirror blurred as one, let in over a band round the foot, so the
            // line where the two meet is blurred away.
            if blurs {
                mirrored
                    .blur(radius: 20, opaque: true)
                    .mask(seam)
            }
        }
        .frame(height: plate + depth, alignment: .top)
        .clipped()
    }

    /// Clear more than `seamReach` points from the card's foot, opaque within a third of that.
    private var seam: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(0, plate - Self.seamReach))
            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.seamReach * 2 / 3)
            Color.white.frame(height: Self.seamReach * 2 / 3)
            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.seamReach * 2 / 3)
            Color.clear
        }
        .frame(height: plate + depth, alignment: .top)
    }

    private static var seamReach: Double { 50 }

    /// The card, and the card turned over under it.
    private var mirrored: some View {
        ZStack(alignment: .top) {
            painted

            // Turned over about its foot, which puts it under the card, and masked to what is
            // under the card. **Masked, not clipped**: a clip tight round a blurred view limits
            // the blur to what the clip keeps.
            Color.clear
                .frame(height: plate + depth)
                .overlay(alignment: .top) {
                    underneath.scaleEffect(x: 1, y: -1, anchor: .bottom)
                }
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: plate)
                        Color.white
                    }
                }
        }
        .frame(height: plate + depth, alignment: .top)
        .clipped()
    }

    /// The picture as the card shows it: sharp at the top, blurred toward the foot. Two blurs,
    /// each let in over its own stretch, so the change from sharp to soft has no line where it
    /// starts. `opaque` keeps the blurred edges from going transparent.
    private var painted: some View {
        ZStack {
            sharp

            if blurs {
                sharp
                    .blur(radius: 10, opaque: true)
                    .mask(ramp(from: blurFrom, to: min(1, blurFrom + 0.3)))
                sharp
                    .blur(radius: 32, opaque: true)
                    .mask(ramp(from: min(0.95, blurFrom + 0.2), to: 1))
            }
        }
        .frame(height: plate)
    }

    /// What is turned over under the card. See ``RunOffReflection``. With no photograph there is
    /// nothing to blur, and the card is turned over as it is.
    @ViewBuilder private var underneath: some View {
        switch reflection {
        case .asDrawn:
            painted
        case .blurred:
            if blurs {
                sharp.blur(radius: 32, opaque: true)
            } else {
                painted
            }
        }
    }

    private var sharp: some View {
        face()
            .frame(height: plate)
            .clipped()
    }

    /// Clear down to `from` of the plate's height and opaque from `to` of it.
    private func ramp(from: Double, to: Double) -> LinearGradient {
        LinearGradient(
            stops: [.init(color: .clear, location: from),
                    .init(color: .white, location: to)],
            startPoint: .top, endPoint: .bottom)
    }
}
