import UIKit
import CoreText
import CoreGraphics
import RPMDesign

/// The frame on the cover of a playlist folder, lettered with the folder's name.
///
/// It is a different drawing from a list's frame (``PlaylistFrame``), so a folder does not look like
/// one more list: a black square with a window cut out of it in the shape of the app's folder icon
/// (round corners, a tab at the top left), a soft glow round the window's edge, and the folder's name
/// centred under it (``RPMDesign/FolderFrameMetrics``). One of the app's own folders shows its
/// photograph through the window (`PlaylistPhotos.folderCover`); a folder somebody made shows a
/// still room in its colours.
///
/// The drawing is inked in the folder's two colours as a list's frame is: its black in the border
/// colour, the glow running from it towards the lettering colour, and the name in the lettering
/// colour. The window stays transparent.
public enum FolderFrame {
    /// The lettered frame at this size, or nil if the drawing did not load.
    ///
    /// - Parameters:
    ///   - name: the folder's name, in the current locale.
    ///   - look: the folder's two inks.
    ///   - edge: the side of the square, in points. The screen scale is applied here.
    @MainActor
    public static func image(name: String, look: GeneratedListLook.Look, edge: CGFloat) -> UIImage? {
        guard edge > 0, let drawing = Self.drawing else { return nil }

        let scale = UIScreen.main.scale
        let pixels = Int((edge * scale).rounded())
        let border = look.border, text = look.text
        let named = "\(name)|\(border.r).\(border.g).\(border.b)|\(text.r).\(text.g).\(text.b)|\(pixels)"
        let key = named as NSString

        if let already = held.object(forKey: key) { return already }

        guard let inked = PlaylistFrame.ramped(drawing, from: look.border, to: look.text) else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        format.opaque = false

        let made = UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format)
            .image { _ in
                UIImage(cgImage: inked).draw(in: CGRect(x: 0, y: 0, width: edge, height: edge))
                letter(name, edge: edge, colour: look.text)
            }

        held.setObject(made, forKey: key)
        return made
    }

    /// Whether the drawing loaded. A folder shows its plain mark when it did not.
    public static var has: Bool { drawing != nil }

    /// Composed frames, emptied by the system under memory pressure.
    @MainActor private static let held = NSCache<NSString, UIImage>()

    /// The drawing, loaded once. A failed load is kept too, so it is not tried again for every row.
    private static let drawing: CGImage? = {
        guard let url = Bundle.module.url(forResource: "FolderFrame", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    /// Sets the name under the folder, in the app's Cabin Bold, with the system font for
    /// letters Cabin does not have.
    @MainActor
    private static func letter(_ name: String, edge: CGFloat, colour: RGB) {
        let face = SharedFaces.cabinBold
        guard let set = FolderFrameMetrics.lettering(name, edge: edge, measuring: { said, size in
            PlaylistFrame.ink(of: said, face: face, size: size)
        }) else { return }

        let font: UIFont = face.flatMap { UIFont(name: $0, size: set.size) }
            ?? .systemFont(ofSize: set.size, weight: .bold)

        // UIKit draws from the top of the line box; the metrics give a baseline. The font's ascent
        // converts between them.
        (name as NSString).draw(
            at: CGPoint(x: set.x, y: set.baseline - font.ascender),
            withAttributes: [.font: font,
                             .foregroundColor: UIColor(red: CGFloat(colour.r) / 255,
                                                       green: CGFloat(colour.g) / 255,
                                                       blue: CGFloat(colour.b) / 255,
                                                       alpha: 1)])
    }
}
