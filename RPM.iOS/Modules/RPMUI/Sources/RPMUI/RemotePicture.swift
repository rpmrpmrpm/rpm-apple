import SwiftUI
import UIKit
import RPMKit

/// A picture from an address, as `AsyncImage` draws one, but loaded with the app's key on a request to the RPM API
/// (``AppKey/owns(_:)``). The API answers 401 to a picture asked for without the key, such as a person's photo or
/// banner, so `AsyncImage` alone never shows one. A picture once loaded is kept in memory, so it shows at once the
/// next time a page draws it.
struct RemotePicture<Content: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    @State private var image: UIImage?

    init(_ url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        ZStack {
            if let image = image ?? url.flatMap({ PictureCache.shared.held($0) }) {
                content(Image(uiImage: image))
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await PictureCache.shared.image(url)
        }
    }
}

/// The pictures ``RemotePicture`` has loaded, by address, and the loading itself.
final class PictureCache: @unchecked Sendable {
    static let shared = PictureCache()

    private let kept = NSCache<NSURL, UIImage>()
    private let session = Wire.session()

    private init() { kept.countLimit = 300 }

    /// The picture already loaded, without loading it.
    func held(_ url: URL) -> UIImage? { kept.object(forKey: url as NSURL) }

    /// The picture, loaded once; nil when it cannot be loaded. A failure is not kept, so it is asked for again.
    func image(_ url: URL) async -> UIImage? {
        if let found = held(url) { return found }
        var request = URLRequest(url: url)
        if AppKey.owns(url) { request.setValue(AppKey.value, forHTTPHeaderField: AppKey.header) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else { return nil }
        kept.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// A picture from an address as an `Image`, loaded as ``RemotePicture`` loads one: for the app, which draws a found
/// picture inside a view of its own, such as a review's cover.
public enum RemotePictures {
    public static func image(_ url: URL) async -> Image? {
        await PictureCache.shared.image(url).map { Image(uiImage: $0) }
    }
}
