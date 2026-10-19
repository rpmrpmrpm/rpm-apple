import SwiftUI
import RPMKit
import RPMLibrary
import RPMArt
import RPMRadio
import RPMSharedUI

/// What each card in the home banner shows. The data is fetched before the card appears on screen,
/// so a card is drawn once, complete. Nothing arrives while the card is being viewed.
///
/// A record's card shows the artist's photograph cut for the plate, the artist's logo and the album
/// cover. A list's card shows its picture. A station's card shows its logo, its background and its
/// line of text. The album covers, list pictures and station logos are drawn by their own views
/// from the stores' memory. This class keeps only what no store holds for the first frame: the
/// photograph cut for the plate, the logo reduced to its box, and the station's line of text. It
/// also keeps whether the card is ready.
///
/// Cards for the plate and both neighbours are prepared while the opening is shown
/// (`TVModel.warmHome`). After every step, the cards on either side of the new plate are prepared,
/// so a card is ready before it is shown. The banner's own step waits for its card. A step made
/// with the remote shows the card as it is and fades in whatever arrives later.
@MainActor
@Observable
final class BannerLooks {
    /// What a record's card shows.
    struct Record {
        /// The artist's photograph cut for the plate, or nil. If nil, the blurred album cover is
        /// used.
        let photo: CGImage?
        /// The artist's logo scaled to fit its box, or nil. If nil, the artist's name is written.
        let logo: CGImage?
        /// The album cover at the card's size. It is also blurred into the background where there
        /// is no photograph.
        let sleeve: CoverArt?
    }

    enum Look {
        case record(Record)
        case list
        case station(line: String?)

        /// Whether nothing on it is missing. A missing part is either the store's answer (for
        /// example, an artist with no logo) or a read that failed (for example, no network). From
        /// here the two look the same. A card with a missing part is requested again the next time
        /// it is prepared. A stored answer costs nothing to ask for again, and a failed read gets
        /// another try.
        var isWhole: Bool {
            switch self {
            case .record(let record): record.photo != nil && record.logo != nil && record.sleeve != nil
            case .list: true
            case .station(let line): line != nil
            }
        }
    }

    /// The plate's size. Every card's photograph is cut for this size, including the neighbours. A
    /// photo cut once is then the same picture at the side and in the middle.
    nonisolated static let plate = CGSize(width: 1480, height: 480)
    /// The album cover on a record's card, and the picture on a list's card.
    static let picture: CGFloat = 220
    /// The logo on a station's card.
    static let stationLogo: CGFloat = 180
    /// The box that the artist's logo is scaled to fit.
    static let logoBox = CGSize(width: 480, height: 64)

    /// The ready cards, by ``name(_:on:)``.
    private(set) var looks: [String: Look] = [:]

    @ObservationIgnored private var asking: [String: Task<Void, Never>] = [:]

    /// The cards whose look has a missing part (``Look/isWhole`` is false). They are requested
    /// again when next prepared.
    @ObservationIgnored private var partial: Set<String> = []

    /// The card for `feature`, or nil while it is not yet prepared.
    func look(_ feature: HomeFeature, on shelf: CloudShelf) -> Look? {
        looks[Self.name(feature, on: shelf)]
    }

    /// Prepares these cards, each once, all at the same time. Returns when every card is ready. A
    /// caller that stops waiting (at the opening's time limit) leaves the work running. The card is
    /// then ready when it is shown, or it fades in what it lacks.
    func prepare(_ features: [HomeFeature], model: TVModel, scale: CGFloat) async {
        let shelf = model.session.viewing
        let waits = features.map { prepare($0, on: shelf, model: model, scale: scale) }
        for wait in waits { await wait.value }
    }

    /// Forgets every card. Used on sign-out and when another collection is opened.
    func forget() {
        for task in asking.values { task.cancel() }
        asking = [:]
        partial = []
        looks = [:]
    }

    private func prepare(_ feature: HomeFeature, on shelf: CloudShelf, model: TVModel, scale: CGFloat) -> Task<Void, Never> {
        let name = Self.name(feature, on: shelf)
        if let running = asking[name] { return running }
        if looks[name] != nil, !partial.contains(name) { return Task {} }

        let task = Task { [weak self] in
            let look = await Self.make(feature, model: model, scale: scale)
            guard let self, !Task.isCancelled else { return }
            // A card already on screen, with no look or a partial one, fades to the new look. A
            // card not yet shown is drawn with the look from the start.
            withAnimation(.easeOut(duration: 0.42)) { self.looks[name] = look }
            if look.isWhole { self.partial.remove(name) } else { self.partial.insert(name) }
            self.asking[name] = nil
        }
        asking[name] = task
        return task
    }

    /// Names the card by owner and feature. The same record on a shelf shared from another account
    /// has its own album cover.
    private static func name(_ feature: HomeFeature, on shelf: CloudShelf) -> String {
        "\(shelf.ownerId)|\(feature.kind)|\(feature.key)"
    }

    private static func make(_ feature: HomeFeature, model: TVModel, scale: CGFloat) async -> Look {
        let session = model.session
        switch feature.kind {
        case .madeForYou:
            guard let set = HomeLists.set(named: feature.key, in: session.playlists) else { return .list }
            _ = await ListArt.load(set, edge: PictureSize.pixels(picture, scale: scale), model: model)
            return .list

        case .radio:
            guard let station = session.homeStations[feature.key] else { return .station(line: nil) }
            let blurbs = model.radio.blurbs
            async let line = blurbs.of(station)
            _ = await StationDress.dress(station, edge: stationLogo, state: model.stations.radioState,
                                         reach: model.reading)
            return .station(line: await line)

        default:
            guard let album = session.albums.first(where: { $0.key == feature.key }) else {
                return .record(Record(photo: nil, logo: nil, sleeve: nil))
            }
            let backdrops = model.backdrops
            let artwork = model.artwork
            let shelf = session.shelves.shelf(ofAlbum: album)
            let box = LetteringBox(tall: Int(logoBox.height * scale), wide: Int(logoBox.width * scale))
            async let photo = photograph(of: album, from: backdrops)
            async let logo = backdrops.logo(artist: album.artist, album: album.album, box: box)
            async let sleeve = artwork.cover(for: album, on: shelf, edge: PictureSize.pixels(picture, scale: scale))
            return .record(Record(photo: await photo, logo: await logo, sleeve: await sleeve))
        }
    }

    /// The artist's wide photograph is tried first. Its crop is chosen by where the face is. The
    /// Android TV banner uses the same first background. If there is no wide photograph, the square
    /// portrait is used.
    nonisolated private static func photograph(of album: CloudAlbum, from backdrops: BackdropStore) async -> CGImage? {
        let scene = ArtScene.forClearLeft(width: Double(plate.width), height: Double(plate.height),
                                          clearTop: 0, clearRight: 1, clearBottom: 1)
        if let wide = await backdrops.backdrop(artist: album.artist, album: album.album, at: 0, cutFor: scene) {
            return wide
        }
        return await backdrops.portrait(artist: album.artist, album: album.album, cutFor: scene)
    }
}
