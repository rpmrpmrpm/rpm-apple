import Foundation
import CoreText

/// The typefaces this module contains: Cabin Bold, which a generated list's frame is lettered in.
///
/// They are registered for the process on first use. The iPhone app's own font registry also finds
/// the file here (``url(_:extension:)``), so the font is bundled only once.
public enum SharedFaces {
    /// The registered name of Cabin Bold, or nil if the file did not load.
    public static let cabinBold: String? = register("Cabin-Bold", "ttf")

    /// The location of one of this module's fonts, for another font registry to use.
    public static func url(_ name: String, extension suffix: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: suffix)
    }

    private static func register(_ name: String, _ suffix: String) -> String? {
        guard let url = url(name, extension: suffix),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first
        else { return nil }

        // If the font is already registered (the iPhone app's registry registered it first), this
        // call fails, but the font is still available under its name.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }
}
