import SwiftUI
import RPMKit
import RPMLibrary
import RPMArt
import RPMRadio
import RPMSharedUI

/// A record's album cover. It fills its box, on a dark well with a music note icon until the cover
/// arrives.
///
/// The cover is requested from `ArtworkStore` at the box size in pixels. It is keyed on the record,
/// so a recycled card never shows another record's cover. A cover the store already holds is drawn
/// on the first frame. Only a cover that has to be fetched fades in. The cover's colours are passed
/// to `onColours`, for a page that lights the room from them.
struct Sleeve: View {
    @Environment(TVModel.self) private var model
    @Environment(\.displayScale) private var scale

    let album: CloudAlbum?
    let edge: CGFloat
    var corner: CGFloat = 10
    var onColours: (SleeveColours) -> Void = { _ in }

    @State private var art: CoverArt?
    @State private var artOf: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let shown = artOf == album?.key ? art : nil
        let drawn = shown ?? album.flatMap {
            model.artwork.coverInMemory(for: $0, on: model.session.shelves.shelf(ofAlbum: $0), edge: pixels)
        }
        ZStack {
            shape.fill(Ink.well)
            if let drawn {
                Image(decorative: drawn.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: edge * 0.22))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(shape)
        .task(id: album?.key) {
            guard let album else { return }
            let shelf = model.session.shelves.shelf(ofAlbum: album)
            let had = model.artwork.coverInMemory(for: album, on: shelf, edge: pixels)
            let found = await model.artwork.cover(for: album, on: shelf, edge: pixels)
            guard !Task.isCancelled else { return }
            var put = Transaction()
            if had == nil { put.animation = .easeOut(duration: 0.25) }
            withTransaction(put) {
                art = found
                artOf = album.key
            }
            if let found { onColours(found.colours) }
        }
    }

    private var pixels: Int { PictureSize.pixels(edge, scale: scale) }
}

/// The number of pixels to request from a picture store, for a picture that is `points` wide on
/// this screen.
///
/// The stores keep pictures at a few sizes (``ArtworkStore/buckets``). A request is served from the
/// first size that is large enough. Without this rule, a card a few pixels over a kept size would
/// be decoded at the next size up. For example, 260 points is 260 pixels on a 1080p Apple TV and
/// 520 pixels on a 4K one. The next size up uses four times the memory, for a sharpness that is not
/// visible from a couch. It would also hold a quarter as many cards in memory. So a size within 3%
/// of a kept size asks for that kept size.
enum PictureSize {
    static func pixels(_ points: CGFloat, scale: CGFloat) -> Int {
        let exact = Int((points * scale).rounded())
        guard let below = ArtworkStore.buckets.last(where: { $0 <= exact }),
              Double(exact) <= Double(below) * 1.03 else { return exact }
        return below
    }
}

/// A list's picture, chosen by ``ListArt``. The order is: the room, for the five generated lists
/// that stand on one. Otherwise the photograph that a generated list includes. Otherwise the
/// picture the computer stored for the list in the cloud. Otherwise the cover of its first record.
/// The generated lists' frame is drawn over the picture, with the list's name on it. The picture is
/// drawn on the first frame if it is already in memory, as a cover is.
struct ListPicture: View {
    @Environment(TVModel.self) private var model
    @Environment(\.displayScale) private var scale

    let set: PlaylistSet
    let edge: CGFloat
    var corner: CGFloat = 10
    /// Whether the room behind the frame's window drifts, where the list stands on one. Each use
    /// sets this value, as on the phone. The room is a shader that runs while the square is on
    /// screen. A square on a plate that is already a live room, or one of many small squares, keeps
    /// the room still.
    let drifts: Bool
    var onColours: (SleeveColours) -> Void = { _ in }

    @State private var art: CoverArt?
    @State private var artOf: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let framed = FramedList.of(set)
        let drawn = (artOf == set.id ? art : nil) ?? ListArt.inMemory(set, edge: pixels, model: model)
        ZStack {
            shape.fill(Color.white.opacity(0x1F / 255))
            if let framed, ListArt.standsOnRoom(set) || drawn == nil && RoomView.works {
                // The five lists with no picture of their own stand on the room, as on the desktop
                // and the phone. A framed list whose picture did not load also stands on the room.
                RoomView(colours: framed.room, sound: .still, foot: 1, running: drifts,
                         breathes: true, zero: .whenShown, seed: set.id)
            } else if let drawn {
                Image(decorative: drawn.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: edge * 0.22))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(width: edge, height: edge)
        .listFrame(framed, edge: edge)
        .clipShape(shape)
        .task(id: set.id) {
            let had = ListArt.inMemory(set, edge: pixels, model: model)
            let found = await ListArt.load(set, edge: pixels, model: model)
            guard !Task.isCancelled else { return }
            var put = Transaction()
            if had == nil { put.animation = .easeOut(duration: 0.25) }
            withTransaction(put) {
                art = found
                artOf = set.id
            }
            if let found { onColours(found.colours) } else if let framed {
                onColours(SleeveColours(accent: nil, dominant: framed.look.trio.mid,
                                        highlight: framed.look.trio.hot, shade: framed.look.trio.deep))
            }
        }
    }

    private var pixels: Int { PictureSize.pixels(edge, scale: scale) }
}

/// Where a list's picture comes from, in the order that ``ListBehind`` gives. The desktop and the
/// phone use the same order: the room, for the five generated lists that stand on one; the
/// photograph that a generated list includes; the picture the computer stored for it; and the cover
/// of its first record. The list's card and the banner's preparation both use this, so they ask the
/// same stores the same question.
enum ListArt {
    /// Whether the list stands on the room and asks no store for a picture. A list whose room
    /// cannot be drawn (because there is no frame in the bundle or no shader) shows its stored
    /// picture instead. On the main actor because `RoomView.works` is.
    @MainActor
    static func standsOnRoom(_ set: PlaylistSet) -> Bool {
        ListBehind.of(set.cut) == .room && FramedList.of(set) != nil && RoomView.works
    }

    /// What is already in memory for this list at this size. It does no fetch and no decode, so it
    /// is fast enough for a first frame. Nil for a list that stands on the room.
    @MainActor
    static func inMemory(_ set: PlaylistSet, edge: Int, model: TVModel) -> CoverArt? {
        switch ListBehind.of(set.cut) {
        case .room where standsOnRoom(set): return nil
        case .photograph(let cut): return PlaylistPhotos.coverInMemory(for: cut, edge: edge)
        case .room, .stored: break
        }
        if let drawn = model.listPictures.pictureInMemory(playlistId: set.picture.id, on: set.shelf, edge: edge) {
            return drawn
        }
        guard let album = firstRecord(set, model: model) else { return nil }
        return model.artwork.coverInMemory(for: album, on: set.shelf, edge: edge)
    }

    /// The picture itself, fetched or composed when it is not in memory. The shipped photograph is
    /// composed off the main thread, because it needs a decode and two draws. Nil for a list that
    /// stands on the room.
    @MainActor
    static func load(_ set: PlaylistSet, edge: Int, model: TVModel) async -> CoverArt? {
        switch ListBehind.of(set.cut) {
        case .room where standsOnRoom(set): return nil
        case .photograph(let cut):
            if let held = PlaylistPhotos.coverInMemory(for: cut, edge: edge) { return held }
            if let made = await Task.detached(priority: .userInitiated, operation: {
                PlaylistPhotos.cover(for: cut, edge: edge)
            }).value { return made }
        case .room, .stored: break
        }
        if let drawn = await model.listPictures.picture(playlistId: set.picture.id, on: set.shelf, edge: edge) {
            return drawn
        }
        guard let album = firstRecord(set, model: model) else { return nil }
        return await model.artwork.cover(for: album, on: set.shelf, edge: edge)
    }

    @MainActor
    private static func firstRecord(_ set: PlaylistSet, model: TVModel) -> CloudAlbum? {
        guard let first = set.tracks.first else { return nil }
        let key = AlbumGrouping.key(for: first)
        return model.session.albums.first { $0.key == key }
    }
}

/// A station's logo on its background, filling its box. It uses the shared `StationFace`. If a
/// station has no logo that loads, the antenna icon is shown instead.
struct StationLogo: View {
    let station: RadioStation
    let edge: CGFloat
    var corner: CGFloat = 10
    var inset: CGFloat? = nil
    var onWearing: (SleeveColours) -> Void = { _ in }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            shape.fill(Color.black.opacity(0x22 / 255))
            StationFace(station: station, edge: edge, inset: inset ?? edge * 4 / 51, onWearing: onWearing) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: edge * 0.36))
                    .foregroundStyle(Color.white.opacity(0x44 / 255))
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0x18 / 255), lineWidth: 1) }
    }
}

/// An artist's photograph in a circle, with the artist's initial until the photo arrives. A photo
/// that is already held is drawn on the first frame.
struct Portrait: View {
    @Environment(TVModel.self) private var model
    @Environment(\.displayScale) private var scale

    let artist: String
    let edge: CGFloat
    var onPicture: (CGImage) -> Void = { _ in }

    @State private var photo: CGImage?
    @State private var photoOf: String?

    var body: some View {
        let drawn = (photoOf == artist ? photo : nil)
            ?? model.portraits.portraitInMemory(of: artist, edge: pixels)
        ZStack {
            Circle().fill(Color.white.opacity(0x1A / 255))
            if let drawn {
                Image(decorative: drawn, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Text(String(artist.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: edge * 0.36, weight: .semibold))
                    .foregroundStyle(Ink.card)
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(Circle())
        .task(id: artist) {
            let had = model.portraits.portraitInMemory(of: artist, edge: pixels)
            let found = await model.portraits.portrait(of: artist, edge: pixels)
            guard !Task.isCancelled else { return }
            var put = Transaction()
            if had == nil { put.animation = .easeOut(duration: 0.3) }
            withTransaction(put) {
                photo = found
                photoOf = artist
            }
            if let found { onPicture(found) }
        }
    }

    private var pixels: Int { PictureSize.pixels(edge, scale: scale) }
}

/// The picture for the favourite songs: a heart on a background in the loved colour, as on the
/// phone's list.
struct FavouritesPicture: View {
    let edge: CGFloat
    var corner: CGFloat = 10

    var body: some View {
        ZStack {
            LinearGradient(colors: [Ink.loved.opacity(0.85), Ink.loved.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "heart.fill")
                .font(.system(size: edge * 0.34))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
