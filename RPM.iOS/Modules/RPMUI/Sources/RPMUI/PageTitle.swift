import SwiftUI

/// The name at the top of a page, in the title face.
///
/// **The part of the font's descent that the word does not use is removed from the bottom.** See
/// ``RPMFont/headerDescentSlack(_:size:)``. The line under the title is then the same distance
/// below the letters on every page. A page whose name has no descender gives the saved space to
/// the content below it.
public struct PageTitle: View {
    private let said: String

    /// Whether the whole descent of the font is removed, with or without a descender. See
    /// ``PageHeading``, which puts its line beside a descender instead of under it.
    private let trimsAllDescent: Bool

    public init(_ said: String) {
        self.said = said
        self.trimsAllDescent = false
    }

    init(_ said: String, trimsAllDescent: Bool) {
        self.said = said
        self.trimsAllDescent = trimsAllDescent
    }

    /// The space between the title and the line under it (the counts, or what the page is).
    /// All pages use this one value, so the headings stay in line when the user switches tabs.
    public static let subtitleGap: Double = 6

    public var body: some View {
        Text(said)
            .font(RPMFont.header())
            .tracking(RPMFont.headerTracking())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.bottom, -(trimsAllDescent ? RPMFont.headerDescentSlack("")
                                                : RPMFont.headerDescentSlack(said)))
    }
}

/// A library view's title, the line under it, and the keys on the title's line.
///
/// **The same height for every title.** The title is laid out as if it had no descender. If it
/// has one, the line under it starts just to the right of the last letter that reaches below the
/// baseline, level with that letter. "playlists" is then as tall as "collection" and "artists",
/// and the tabs under the three headers do not move when the user switches between them.
struct PageHeading<Keys: View>: View {
    private let title: String
    private let line: String
    private let keys: Keys

    init(_ title: String, line: String, @ViewBuilder keys: () -> Keys) {
        self.title = title
        self.line = line
        self.keys = keys()
    }

    /// The space between the last descender and the start of the line next to it.
    private static var besideDescender: Double { 6 }

    var body: some View {
        let end = RPMFont.headerDescenderEnd(title)

        VStack(alignment: .leading, spacing: PageTitle.subtitleGap) {
            PageTitle(title, trimsAllDescent: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) { keys }

            Text(line)
                .rpmKicker()
                .lineLimit(1)
                .padding(.leading, end > 0 ? end + Self.besideDescender : 0)
        }
    }
}
