import Foundation
import CoreGraphics
import RPMDesign
import RPMLibrary

/// The photograph a generated list wears behind its frame. It ships with the app.
///
/// These are the desktop's own files (`RPM.Desktop/Assets/PlaylistPhotos`). The desktop chooses them in
/// `scripts/playlist-photos.json`. `scripts/gen_playlist_photos_phone.py` copies them here, together with the
/// table of which list wears which (`PlaylistPhotosData.swift`). Without them, the phone would show the drawn
/// figure that the desktop sends for every generated list. A list that wears a photograph on the computer
/// would then wear a different picture on the phone.
///
/// The files are the bare photographs. The list's colour is added here, the same way `GeneratedCoverService.Framed`
/// adds it on the desktop. The photograph fills the square, and the list's tint is laid over it with the `color`
/// blend mode at ``tintStrength``. That blend keeps the photograph's light and shade, and replaces its hue and
/// saturation. So a photograph and a drawn figure sit together in the same colours. The desktop also stamps
/// `PlaylistMark` when `Assets/PlaylistMark.png` exists. That file is not in the repository, so neither app draws
/// a mark.
///
/// A list with no entry, a file missing from the bundle, or bytes that will not decode each give nil. The caller
/// then asks the store for the figure instead.
public enum PlaylistPhotos {
    /// How much of the list's colour is laid over the photograph. It matches the desktop's
    /// `GeneratedCoverService.TintStrength`. The two values must match, or one list would show two different covers.
    static let tintStrength: CGFloat = 0.72

    /// Whether this list ships a photograph.
    public static func has(_ cut: GeneratedCut) -> Bool { files[cut] != nil }

    /// The list's photograph, washed in its colour, as a square at the size asked for.
    ///
    /// This is synchronous and not tied to an actor. It is a decode and two draws at a few hundred pixels. The
    /// caller runs it off the main actor. (`CloudCovers.picture(of:edge:)` is a nonisolated async function.)
    ///
    /// - Parameter edge: the square the caller draws, in pixels. It is rounded up to one of ``ArtworkStore/buckets``
    ///   and capped at the shipped file's own size. So a pinch on the wall composes each list at no more than three
    ///   sizes.
    public static func cover(for cut: GeneratedCut, edge: Int) -> CoverArt? {
        guard edge > 0, let file = files[cut],
              let tint = GeneratedListLook.of(kind: cut.kind, genre: cut.genre,
                                              decade: cut.decade)?.tint
        else { return nil }

        let size = min(ArtworkStore.bucket(holding: edge), shippedEdge)
        let key = Self.key(file, size)

        if let held = held.object(forKey: key) { return held.art }

        guard let url = Bundle.module.url(forResource: file, withExtension: nil,
                                          subdirectory: "PlaylistPhotos"),
              let data = try? Data(contentsOf: url),
              let photo = Thumbnail.of(data, edge: size),
              let washed = washed(photo, in: tint, edge: size)
        else { return nil }

        let art = CoverArt(image: washed, colours: Thumbnail.colours(of: washed))
        held.setObject(Entry(art), forKey: key, cost: size * size * 4)
        return art
    }

    /// The cover ``cover(for:edge:)`` has already composed for this list at this size, or nil. This does no decode
    /// and no draw, so a view can ask for it on the main thread when it draws its first frame.
    public static func coverInMemory(for cut: GeneratedCut, edge: Int) -> CoverArt? {
        guard edge > 0, let file = files[cut] else { return nil }
        return held.object(forKey: key(file, min(ArtworkStore.bucket(holding: edge), shippedEdge)))?.art
    }

    private static func key(_ file: String, _ size: Int) -> NSString {
        "\(file)@\(size)" as NSString
    }

    /// The photograph scaled to fill a square of `edge` pixels, centred, with `tint` laid over it.
    ///
    /// It is filled rather than fitted, as on the desktop. The shipped files are already square, so nothing is
    /// cropped. A photograph of another shape that is added by hand loses its edges, rather than gaining bars.
    ///
    /// Everything is in sRGB, which is what the palette's values and the shipped JPEGs use. The tint is made in the
    /// context's own colour space. `CGColor(red:green:blue:alpha:)` uses Generic RGB on macOS, and would be converted
    /// on the way in. That shifts the wash away from the desktop's colours.
    static func washed(_ photo: CGImage, in tint: RGB, edge: Int) -> CGImage? {
        guard photo.width > 0, photo.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let black = CGColor(colorSpace: space, components: [0, 0, 0, 1]),
              let wash = CGColor(colorSpace: space,
                                 components: [CGFloat(tint.r) / 255, CGFloat(tint.g) / 255,
                                              CGFloat(tint.b) / 255, tintStrength])
        else { return nil }

        let square = CGRect(x: 0, y: 0, width: edge, height: edge)
        context.setFillColor(black)
        context.fill(square)

        let fill = max(CGFloat(edge) / CGFloat(photo.width), CGFloat(edge) / CGFloat(photo.height))
        let width = CGFloat(photo.width) * fill, height = CGFloat(photo.height) * fill
        context.interpolationQuality = .high
        context.draw(photo, in: CGRect(x: (CGFloat(edge) - width) / 2,
                                       y: (CGFloat(edge) - height) / 2,
                                       width: width, height: height))

        // `color` takes hue and saturation from the fill, and luminosity from what is under it. This is the same
        // non-separable blend as Skia's SKBlendMode.Color, which the desktop uses.
        context.setBlendMode(.color)
        context.setFillColor(wash)
        context.fill(square)

        return context.makeImage()
    }

    private final class Entry {
        let art: CoverArt
        init(_ art: CoverArt) { self.art = art }
    }

    /// Composed covers by file and size. The system empties this under memory pressure, as it does every picture
    /// cache in the app. `NSCache` is thread-safe. That is why `nonisolated(unsafe)` is allowed.
    private nonisolated(unsafe) static let held: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
}
