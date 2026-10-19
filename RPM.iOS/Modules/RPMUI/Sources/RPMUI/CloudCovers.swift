import SwiftUI
import RPMKit
import RPMLibrary
import RPMArt

/// Supplies the covers for the wall from the cloud store.
///
/// This is the whole adapter. `ArtworkStore` returns `CGImage` and knows nothing about the
/// screen. This type converts a width in points to a width in pixels, finds the shelf of the
/// record, and wraps the result for SwiftUI.
///
/// **The shelf is looked up here and not passed in**, because it belongs to the record and
/// not to the tile. A wall can show a borrowed collection, and a borrowed collection has its
/// own covers. `TrackShelves` is the only place that knows, and it looks up by row.
public struct CloudCovers: CoverStore {
    private let store: ArtworkStore

    /// The pictures of playlists. It is a separate store from the records' store (see
    /// ``PlaylistPictures``). It is optional: a surface built without it draws rows without
    /// playlist pictures.
    private let lists: PlaylistPictures?

    /// Photographs of artists. Optional, like the playlist pictures: a surface built without
    /// it draws boxes on their own background, as for an artist with no photograph.
    private let portraits: ArtistPortraits?

    private let shelves: TrackShelves
    private let scale: Double

    /// `scale` is the screen's scale. A card 170 points wide at scale 3 asks for 510 pixels.
    /// It is passed in and not read here, because this type is called from a background task
    /// and the screen belongs to the main actor.
    public init(store: ArtworkStore, lists: PlaylistPictures? = nil,
                portraits: ArtistPortraits? = nil,
                shelves: TrackShelves, scale: Double) {
        self.store = store
        self.lists = lists
        self.portraits = portraits
        self.shelves = shelves
        self.scale = scale
    }

    public func band(for edge: Double) -> Int {
        ArtworkStore.bucket(holding: pixels(edge))
    }

    private func pixels(_ edge: Double) -> Int { Int((edge * scale).rounded(.up)) }

    public func cover(for album: CloudAlbum, edge: Double) async -> Cover? {
        let shelf = shelves.shelf(ofAlbum: album)

        guard let art = await store.cover(for: album, on: shelf, edge: pixels(edge))
        else { return nil }

        // Decorative: the record's name and artist are next to the cover, so a screen reader
        // should not announce the cover as well.
        return Cover(image: Image(decorative: art.image, scale: 1), colours: art.colours)
    }

    /// Returns the bundled photograph for a generated list that has one, and the store's picture
    /// otherwise. The desktop chooses in the same order (`GeneratedCover.BehindAsync`), so a list
    /// shows the same picture on both. The store may hold a picture for a list that has a
    /// photograph, but it is not asked for it.
    ///
    /// Nonisolated and async, so the decode and wash in ``PlaylistPhotos/cover(for:edge:)`` run off
    /// the main actor that the squares ask from.
    public func picture(of list: ListPicture, edge: Double) async -> Cover? {
        if let cut = list.cut, let photo = PlaylistPhotos.cover(for: cut, edge: pixels(edge)) {
            // Decorative: the list's name is next to it.
            return Cover(image: Image(decorative: photo.image, scale: 1), colours: photo.colours)
        }

        guard let lists,
              let art = await lists.picture(playlistId: list.id, on: list.shelf, edge: pixels(edge))
        else { return nil }

        // Decorative: the list's name is next to the picture, so a screen reader should not
        // announce the picture as well.
        //
        // The colours are returned with it. The banner lights a list's card with these colours,
        // as the desktop does. See HomeFeatureCard.
        return Cover(image: Image(decorative: art.image, scale: 1), colours: art.colours)
    }

    public func portrait(of artist: String, edge: Double) async -> Cover? {
        guard let portraits,
              let picture = await portraits.portrait(of: artist, edge: pixels(edge))
        else { return nil }

        // No accent colour is taken from it. A photograph is not a cover: the boxes use the
        // colour of the artist's first RECORD, which the wall already has. A colour taken from a
        // press photo would come from the background of the studio.
        //
        // Decorative: the box shows the artist's name as text across it.
        return Cover(image: Image(decorative: picture, scale: 1), accent: nil)
    }
}
