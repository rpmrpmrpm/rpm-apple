import SwiftUI
import UIKit
import RPMKit

/// A person's photo in a circle, or the first letter of their name when they have none or it has
/// not loaded.
struct PersonPicture: View {
    private let url: URL?
    private let name: String
    private let size: CGFloat

    init(_ url: URL?, name: String, size: CGFloat) {
        self.url = url
        self.name = name
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle().fill(RPMInk.white(0x26 / 255))

            Text(initial)
                .font(RPMFont.text(size * 0.42, weight: .semibold))
                .foregroundStyle(RPMInk.white(0xDD / 255))

            if let url {
                RemotePicture(url) { image in
                    image.resizable().scaledToFill()
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = name.first, first.isLetter || first.isNumber else { return "?" }
        return String(first).uppercased()
    }
}

/// Makes a picked photo small enough for the server: JPEG, cropped to the shape it is shown in.
enum PicturePrep {
    /// The photo: a square of 512 points, at most 500 KB (the server takes 512 KB).
    static func avatar(_ data: Data) -> Data? {
        jpeg(data, size: CGSize(width: 512, height: 512), under: 500_000)
    }

    /// The banner: 1500 by 500, at most 1.9 MB (the server takes 2 MB).
    static func banner(_ data: Data) -> Data? {
        jpeg(data, size: CGSize(width: 1500, height: 500), under: 1_900_000)
    }

    /// Draws the picture to fill `size`, cut at the centre, and lowers the JPEG quality until it
    /// fits. Nil when the data is not a picture, or it does not fit even at the lowest quality.
    private static func jpeg(_ data: Data, size: CGSize, under limit: Int) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }

        // Never larger than the photo itself.
        let fill = max(size.width / image.size.width, size.height / image.size.height)
        let target = fill > 1
            ? CGSize(width: (size.width / fill).rounded(), height: (size.height / fill).rounded())
            : size
        let scale = max(target.width / image.size.width, target.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // `UIImage.draw` follows the photo's orientation, so a portrait photo stays upright.
        let picture = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (target.width - drawn.width) / 2, y: (target.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }

        for quality in [0.85, 0.7, 0.55, 0.4] {
            if let out = picture.jpegData(compressionQuality: quality), out.count <= limit { return out }
        }
        return nil
    }
}
