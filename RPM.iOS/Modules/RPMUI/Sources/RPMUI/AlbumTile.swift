import SwiftUI
import RPMKit
import RPMLibrary
import RPMDesign
import RPMArt

/// A sleeve, and what colour it is.
///
/// The two are kept together because only the code that loaded the bytes can say: reading
/// a picture's colour needs a decode and a downscale, and a wall of two thousand cards
/// that each worked it out would do that two thousand times for the ten answers it can
/// have.
public struct Cover: Sendable {
    public let image: Image

    /// Everything the picture was read for, in one reading (see ``SleeveColours``). The room a
    /// banner card is lit in is painted from these, so they travel with the picture
    /// and nobody has to read them a second time.
    public let colours: SleeveColours

    /// The accent this sleeve snapped to, or nil where it has no colour in it to be
    /// near anything. See `RPMPalette.nearest`: a black-and-white press shot keeps
    /// the tone the picture actually gave.
    public var accent: Accent? { colours.accent }

    public init(image: Image, colours: SleeveColours) {
        self.image = image
        self.colours = colours
    }

    /// A picture with only its accent known. What a preview and a stand-in store have.
    public init(image: Image, accent: Accent?) {
        self.init(image: image,
                  colours: SleeveColours(accent: accent, dominant: nil, highlight: nil))
    }
}

/// Where a cover comes from.
///
/// A protocol, so the wall can be built and looked at before the artwork pipeline
/// exists, and so a preview can hand over pictures without a network. The store
/// answers nil for a record it has nothing for, which is the ordinary case on a
/// first scroll and not a failure.
public protocol CoverStore: Sendable {
    /// `edge` is the width the sleeve will be drawn at, **in points**. The store
    /// decodes to fit it: a card a hundred and seventy points wide has no use for a
    /// three-thousand-pixel scan, and decoding one for each of six hundred records
    /// uses so much memory that the system can end the app.
    func cover(for album: CloudAlbum, edge: Double) async -> Cover?

    /// Which widths this store would answer with the same picture.
    ///
    /// **What stops a pinch being a fetch per frame.** A card is a different number
    /// of points at every step of a gesture, and a tile that re-asked on each one
    /// would ask sixty times a second. A tile re-asks when this number changes, so
    /// a store that keeps three sizes is asked at most three times across a whole
    /// pinch, and a sleeve is still redrawn sharp instead of staying at the size it
    /// first arrived at.
    func band(for edge: Double) -> Int

    /// The picture a PLAYLIST shows, which is a different question from a record's.
    ///
    /// A playlist has a cover of its own: for one the app cut, the photograph shipped for it
    /// where it has one and otherwise the figure the computer drew; for one somebody made, four
    /// records or a photograph, drawn on the computer and sent up. Nil is the ordinary answer
    /// and means the row falls back to the sleeve of the record the playlist opens on.
    ///
    /// Takes a ``ListPicture`` rather than an id, because a generated list's cut decides which of
    /// the two it shows. See ``CloudCovers/picture(of:edge:)``.
    func picture(of list: ListPicture, edge: Double) async -> Cover?

    /// A photograph of an ARTIST, which is not a cover of anything.
    ///
    /// The one picture in the app that is looked up by name. A cover guessed from a name can
    /// be the wrong pressing without anything on screen saying so, but a photograph of the
    /// wrong band is easy to see. Nil is the ordinary answer,
    /// because most artists in most libraries have no photograph anywhere.
    func portrait(of artist: String, edge: Double) async -> Cover?
}

extension CoverStore {
    /// One band, for a store where every width is the same answer.
    public func band(for edge: Double) -> Int { 0 }

    /// Nothing, for a store that has no pictures of artists (the stand-ins a preview
    /// and a test hand over).
    public func portrait(of artist: String, edge: Double) async -> Cover? { nil }

    /// Nothing, for a store that has no pictures of playlists (the stand-ins a preview
    /// and a test hand over).
    public func picture(of list: ListPicture, edge: Double) async -> Cover? { nil }

    /// The sleeve of the record a **track** belongs to.
    ///
    /// A track does not carry a cover; a record does. So a playlist shows the sleeve
    /// of whatever it opens with, which is the closest true thing it has to one of
    /// its own. The way to that picture is the same grouping key the wall drew
    /// the record under.
    public func cover(for track: CloudTrack, edge: Double) async -> Cover? {
        await cover(for: CloudAlbum(key: AlbumGrouping.key(for: track),
                                    album: track.album ?? "",
                                    artist: track.artist ?? "",
                                    tracks: [track]),
                    edge: edge)
    }
}

/// One record on the wall: the sleeve, its name, and who made it.
///
/// Every figure comes from `AlbumCaption`, and none of them is written here.
/// **Every card in a row shares an art edge and therefore shares its height**, and
/// a card that sized its own writing would be a row of a different height from the
/// one beside it.
public struct AlbumTile: View {
    private let album: CloudAlbum
    private let art: Double
    private let covers: any CoverStore

    @State private var cover: Cover?

    /// Whether this record can be played now. Offline, a record with nothing on the phone
    /// is greyed: still there to look at, not there to play.
    @Environment(\.rpmPlayable) private var playable

    public init(album: CloudAlbum, art: Double, covers: any CoverStore) {
        self.album = album
        self.art = art
        self.covers = covers
    }

    private var caption: AlbumCaption { .of(art: art) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sleeve
                .frame(width: art, height: art)
                // Ten, the same corner radius as the desktop card. One rounded shape
                // carries the ground, the hairline and the clip: a rounded corner is a
                // clipped layer, and a wall has many of them, so it costs frame time.
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                }

            Spacer().frame(height: AlbumCaption.artGap)

            Text(album.album)
                .font(.system(size: caption.album, weight: .medium))
                .lineLimit(1)
                .frame(height: caption.albumLine, alignment: .leading)

            Spacer().frame(height: AlbumCaption.lineGap)

            Text(album.artist)
                .font(.system(size: caption.artist))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: caption.artistLine, alignment: .leading)

            Spacer().frame(height: AlbumCaption.below)
        }
        .frame(width: art, height: caption.card, alignment: .topLeading)
        .saturation(playable.canPlay(album.key) ? 1 : 0)
        .opacity(playable.canPlay(album.key) ? 1 : 0.35)
        .animation(.easeOut(duration: 0.25), value: playable.canPlay(album.key))
        // The whole card answers a tap, not just the sleeve: a finger aimed at the
        // title of a record is aimed at the record.
        .contentShape(Rectangle())
        .task(id: Wanted(album: album.key, band: covers.band(for: art))) { await load() }
    }

    /// The empty sleeve, as the desktop draws it: the card's own dark ground with a
    /// faint record on it. The album page, the shelf rows and the mini player use the same
    /// well and glyph, so a record with no cover looks the same everywhere.
    private var sleeve: some View {
        ZStack {
            Color.black.opacity(0x22 / 255)

            if let cover {
                Sleeve(image: cover.image)
            } else {
                // Sized from the art edge rather than fixed at the desktop's 34: the
                // wall here is pinched between one column and four, and a glyph that
                // suits two across is huge at one and tiny at four. Limited to the
                // sizes the rest of the app draws it at: 16 on a shelf row and 52 on an
                // album page.
                Text(Glyph.record)
                    .font(RPMFont.icon(min(max(art * 0.2, 16), 52)))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
    }

    /// What this card is waiting for: which record, at which of the sizes the store
    /// keeps. Both, because a recycled cell changes the first and a pinch changes
    /// the second.
    private struct Wanted: Hashable {
        let album: String
        let band: Int
    }

    private func load() async {
        // Cleared first, so a recycled card never shows the last record's sleeve
        // for a frame while this one's is being fetched.
        cover = nil
        cover = await covers.cover(for: album, edge: art)
    }
}
