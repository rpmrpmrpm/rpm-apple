import SwiftUI
import RPMArt
import RPMSharedUI

/// The desktop's photograph for each genre, cut for the TV's genre box (about 1.74 to 1) by
/// `scripts/gen_tv_genre_photos.py`, which writes `GenrePhotos/genre-<slug>.jpg` here as it writes the
/// Android TV's. Decoded off the main thread at the size drawn, and kept for the life of the app: there
/// are 36 of them.
@MainActor
enum GenrePhotos {
    /// The photograph's width against its height, the script's `SHAPE`.
    static let shape: CGFloat = 0.5625 / (0.27 * 1.2)

    private static var held: [String: CGImage] = [:]

    /// The file's name for `genre`: the desktop's slug ("Hip-Hop / Rap" is hip-hop-rap, "R&B" is r-b).
    static func slug(_ genre: String) -> String {
        var out = ""
        var gap = false
        for scalar in genre.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if gap, !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                gap = false
            } else {
                gap = true
            }
        }
        return out
    }

    /// Whether the app has a photograph for `genre`.
    static func has(_ genre: String) -> Bool { url(genre) != nil }

    /// The photograph at `edge` pixels across, if it has been decoded at that size.
    static func held(_ genre: String, edge: Int) -> CGImage? { held[key(genre, edge)] }

    /// The photograph at `edge` pixels across, decoded off the main thread the first time.
    static func photo(_ genre: String, edge: Int) async -> CGImage? {
        let key = key(genre, edge)
        if let kept = held[key] { return kept }
        guard let url = url(genre) else { return nil }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return Thumbnail.of(data, edge: edge)
        }.value
        if let image { held[key] = image }
        return image
    }

    private static func url(_ genre: String) -> URL? {
        Bundle.main.url(forResource: "genre-" + slug(genre), withExtension: "jpg")
    }

    private static func key(_ genre: String, _ edge: Int) -> String { "\(edge)|\(slug(genre))" }
}

/// A genre's photograph, filling the frame it is given, faded in when it is decoded.
struct GenrePhoto: View {
    @Environment(\.displayScale) private var scale
    let genre: String
    /// How wide it is drawn, in points.
    let width: CGFloat

    @State private var picture: CGImage?

    var body: some View {
        let pixels = Int((width * scale).rounded(.up))
        let shown = picture ?? GenrePhotos.held(genre, edge: pixels)
        Color.clear
            .overlay {
                if let shown {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: "\(genre)|\(pixels)") {
                let found = await GenrePhotos.photo(genre, edge: pixels)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { picture = found }
            }
    }
}
