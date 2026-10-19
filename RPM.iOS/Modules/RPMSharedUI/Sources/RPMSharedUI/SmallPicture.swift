import UIKit
import RPMKit

/// Small pictures from third-party URLs, fetched once per launch.
///
/// A station's logo and a user's profile photo have the same needs: a URL that this app does not
/// own, a few kilobytes of data, a 40-point area to draw it in, and a list that scrolls past the
/// same row many times. One shared type serves all callers.
///
/// **Kept in memory only.** A picture this small is worth one request per launch, and a disk cache
/// of other people's images would need cleaning up.
public enum SmallPictures {
    /// `NSCache` is thread-safe and evicts entries itself under memory pressure, but it is not
    /// `Sendable`. `nonisolated(unsafe)` is needed for that reason and is safe, because every use
    /// here is one of its own atomic operations.
    private nonisolated(unsafe) static let held = NSCache<NSString, UIImage>()

    /// The addresses that gave no usable picture. They are kept apart from the cache because a
    /// failed address has no image to store, and asking again on every scroll would make a huge
    /// number of failing requests.
    private nonisolated(unsafe) static let refused = NSCache<NSString, NSNumber>()

    /// - Parameter edge: the size to keep the picture at: the size it will be drawn, and no bigger.
    ///   Images at these addresses range from a 16-pixel favicon to a 2000-pixel logo, and keeping
    ///   large ones at full size would use too much memory in a long list.
    /// - Parameter reach: the current network state. **No default**: these pictures are decoration
    ///   fetched by address (a shelf owner's avatar from the RPM API, a station's logo from a
    ///   volunteer-run directory), and on a dead network each request waits for the full timeout.
    ///   A row can be drawn without its picture, but a list of forty rows that each wait makes the
    ///   screen appear to hang.
    ///
    ///   A failure is remembered as refused only when it is an answer about the picture: a 404 or
    ///   other 4xx, or a body that is not a picture. A request with no answer, a 5xx, 408 or 429,
    ///   and a refusal of the request itself (401, or 403 from the RPM API) say nothing about the
    ///   picture, so the request is made again next time.
    public static func of(_ url: URL, edge: CGFloat, reach: Reach) async -> UIImage? {
        guard url.scheme?.hasPrefix("http") == true else { return nil }
        guard reach.isOnline else { return nil }

        // The size is part of the key: two callers that draw the same picture at different sizes
        // must not receive each other's image.
        let key = "\(Int(edge))|\(url.absoluteString)" as NSString
        if let known = held.object(forKey: key) { return known }
        if refused.object(forKey: key) != nil { return nil }

        // A shelf owner's photo is at the RPM API's profiles/{id}/avatar, which refuses a request
        // without the app key. The key is sent to that host only.
        var request = URLRequest(url: url)
        let ours = AppKey.owns(url)
        if ours { request.setValue(AppKey.value, forHTTPHeaderField: AppKey.header) }

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            let aboutThePicture = !(status == 401 || (status == 403 && ours)
                                    || status >= 500 || status == 408 || status == 429)
            if aboutThePicture { refused.setObject(1, forKey: key) }
            return nil
        }

        guard let picture = UIImage(data: data) else {
            refused.setObject(1, forKey: key)
            return nil
        }

        let fitted = picture.fitted(to: edge)
        held.setObject(fitted, forKey: key)
        return fitted
    }

    /// The picture that ``of(_:edge:reach:)`` has stored for this address at this size, or nil. It
    /// makes no request, so a view can draw the picture on its first frame and not a placeholder.
    public static func inMemory(_ url: URL, edge: CGFloat) -> UIImage? {
        held.object(forKey: "\(Int(edge))|\(url.absoluteString)" as NSString)
    }

    /// A picture that the caller fetches itself, through the API and not from a third-party
    /// address: a station's logo as RPM stores it. It is stored and refused under `key` like the
    /// others.
    ///
    /// - Parameter fetch: returns nil when there is no picture, which is remembered for the launch.
    ///   A thrown error is not remembered: the request got no answer about this picture, and a
    ///   cached refusal would outlast whatever caused the error.
    public static func of(key: String, edge: CGFloat,
                   fetch: @Sendable () async throws -> Data?) async -> UIImage? {
        let key = "\(Int(edge))|\(key)" as NSString
        if let known = held.object(forKey: key) { return known }
        if refused.object(forKey: key) != nil { return nil }

        let data: Data?
        do { data = try await fetch() } catch { return nil }

        // No picture, or one this decoder cannot read. The API serves a drawing as SVG, which
        // `UIImage` cannot open; the caller then tries the next address it has.
        guard let data, let picture = UIImage(data: data) else {
            refused.setObject(1, forKey: key)
            return nil
        }

        let fitted = picture.fitted(to: edge)
        held.setObject(fitted, forKey: key)
        return fitted
    }
}

extension UIImage {
    /// The same picture, no wider or taller than this, redrawn once at the size it will be shown.
    public func fitted(to edge: CGFloat) -> UIImage {
        let side = Swift.max(size.width, size.height)
        guard side > edge, side > 0 else { return self }

        let scale = edge / side
        let box = CGSize(width: (size.width * scale).rounded(),
                         height: (size.height * scale).rounded())

        return UIGraphicsImageRenderer(size: box).image { _ in
            draw(in: CGRect(origin: .zero, size: box))
        }
    }
}
