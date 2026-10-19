import SwiftUI
import RPMKit
import RPMLibrary

/// Three lines of what Wikipedia says about a record or an artist, with a glass "Read more" button
/// at the end of the third line when the text is longer than that.
///
/// The whole block is one key and opens ``AboutSheet``, also when the text fits: the sheet is where
/// the Wikipedia credit is, and Wikipedia's licence asks for one wherever its text is shown.
///
/// The paragraphs are run together here. Three lines with a blank line in the middle is two lines
/// of text.
struct AboutText: View {
    let article: EncyclopediaArticle
    let onOpen: () -> Void

    private static let lines = 3

    /// The description's font and colour. The mood list's sentence on the playlist page uses them
    /// too, so the two pages look the same.
    static let font = RPMFont.display(14)
    static let ink = RPMInk.white(0xB3 / 255)

    /// The space between lines. The mood sentence on the playlist page uses it too.
    ///
    /// The button is centred on the last line and taller than it, so it reaches above that line by
    /// ``rise``: about 3 pt at the default text size (a 24 pt button on an 18 pt line) and 5 pt at
    /// the smallest. With this spacing that part of the button is over the space between the lines,
    /// with at least 2 pt to spare, and not over the line above. SwiftUI adds it between lines
    /// only, not after the last one, so the bottom of the text is the bottom of the last line.
    static let lineSpacing: CGFloat = 7

    /// The fade that runs into "Read more", so the words fade out under the button instead of
    /// being cut off sharply.
    private static let fade: CGFloat = 28

    /// The space between the end of the fade and the button.
    private static let gap: CGFloat = 6

    /// The text's height at three lines, and at as many as it needs. More than three lines of text
    /// is what puts the key on.
    @State private var shown: CGFloat = 0
    @State private var whole: CGFloat = 0

    /// One line of this font, and the button's size: the size of the gap cut out of the last line.
    @State private var line: CGFloat = 0
    @State private var key: CGSize = .zero

    /// How far the button stands above and below the last line. It is centred on that line and
    /// taller than it.
    private var rise: CGFloat { max(0, (key.height - line) / 2) }

    private var clipped: Bool { whole > shown + 1 }

    /// Whether the fade-in has run. The text fades in rather than the page around it animating: see
    /// ``AboutRead/read(_:from:into:)``.
    @State private var faded = false

    private var words: String { article.paragraphs.joined(separator: " ") }

    var body: some View {
        Button(action: onOpen) {
            Text(words)
                .font(Self.font)
                .foregroundStyle(Self.ink)
                .lineSpacing(Self.lineSpacing)
                .multilineTextAlignment(.leading)
                .lineLimit(Self.lines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .measure { shown = $0.height }
                .background(alignment: .topLeading) {
                    // The same text unclipped, and one line of it, measured at the same width and
                    // never drawn.
                    ZStack(alignment: .topLeading) {
                        Text(words)
                            .font(Self.font)
                            .lineSpacing(Self.lineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .measure { whole = $0.height }
                        Text(verbatim: "A")
                            .font(Self.font)
                            .lineLimit(1)
                            .measure { line = $0.height }
                    }
                    .hidden()
                }
                .mask { cut }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Loc.get("Rpm_About_ReadMore"))
        // Over the text button rather than inside its label, so the glass answers its own press.
        // Both open the sheet.
        .overlay(alignment: .bottomTrailing) {
            if clipped { readMore.offset(y: rise) }
        }
        // Opacity only, in a transaction of its own after the text is laid out, so the fade cannot
        // take any change of layout along with it.
        .opacity(faded ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { faded = true } }
    }

    /// Everything, or everything but the end of the last line, where the button sits, with a fade
    /// into it. The last line only: the part of the button above it is over the space between the
    /// lines (see ``lineSpacing``), so there is nothing of the line above to cut.
    @ViewBuilder
    private var cut: some View {
        if clipped, line > 0 {
            VStack(spacing: 0) {
                Rectangle()
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.fade)
                    Color.clear.frame(width: key.width + Self.gap)
                }
                .frame(height: line)
            }
        } else {
            Rectangle()
        }
    }

    private var readMore: some View {
        Button(Loc.get("Rpm_About_ReadMore"), action: onOpen)
            .buttonStyle(RPMGlassButton(.ghost, radius: 12, height: 24, stretches: false,
                                        inset: 11, size: 12))
            .fixedSize()
            .measure { key = $0 }
    }
}

/// The text a page holds, and the subject it was read for.
///
/// A page shows the text only while `id` is its own subject's id. The page can be handed another
/// record or renamed artist under the same view, and a read for the old one can land after that;
/// comparing ids means neither can put the old text under the new name.
struct AboutRead: Equatable {
    let id: String
    let article: EncyclopediaArticle?

    /// What the store already knows, for a page's first frame.
    @MainActor
    init(_ subject: ArticleStore.Subject, in articles: ArticleStore) {
        self.init(id: subject.id, article: articles.cached(subject))
    }

    init(id: String, article: EncyclopediaArticle?) {
        self.id = id
        self.article = article
    }

    func article(for subject: ArticleStore.Subject) -> EncyclopediaArticle? {
        id == subject.id ? article : nil
    }

    /// Reads the text for `subject` into `held`: what the store knows at once, then its answer.
    /// Run from the page's `.task(id: subject.id)`, which is cancelled when the subject changes.
    @MainActor
    static func read(_ subject: ArticleStore.Subject, from articles: ArticleStore,
                     into held: Binding<AboutRead>) async {
        if held.wrappedValue.id != subject.id {
            held.wrappedValue = AboutRead(subject, in: articles)
        }

        let found = await articles.article(subject)
        guard !Task.isCancelled, held.wrappedValue != AboutRead(id: subject.id, article: found)
        else { return }

        // Not animated. Both pages are Lists, and a List row that changes height under an animation
        // grows its cell while the row's contents sit centred in it, so everything in the header
        // slides up and back down. On both pages the text lands under the name and above the keys,
        // so the header row grows by its height in one step, and the text fades itself in.
        held.wrappedValue = AboutRead(id: subject.id, article: found)
    }
}

/// What the sheet shows: the text, and what it is about.
///
/// The name is taken when the key is pressed, so the sheet keeps saying what it was opened for if
/// the page behind it changes while it is up.
struct AboutReading: Identifiable {
    /// "About the album", "About the artist".
    let heading: String
    let name: String
    let article: EncyclopediaArticle

    var id: String { article.id }
}

/// The whole of the text, with the Wikipedia credit beside Close.
///
/// The app's popup, as ``WriteReviewSheet`` and ``PlaylistPickSheet`` are: the page dimmed behind it
/// (a tap there closes it), a glass card in the middle, the heading with what it is about under it,
/// and the keys along the foot. The text scrolls inside the card when it is longer than the screen
/// allows; a short one makes a short card.
struct AboutSheet: View {
    let reading: AboutReading
    let onClose: () -> Void

    @Environment(\.openURL) private var openUrl

    /// The text's own height, so a short article is not given a tall empty card.
    @State private var textHeight: CGFloat = 0

    var body: some View {
        GeometryReader { screen in
            ZStack {
                Color.black.opacity(0xB3 / 255)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.heading)
                            .font(RPMFont.displayBold(19))
                            .foregroundStyle(.white)

                        Text(reading.name).rpmKicker().lineLimit(1)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(reading.article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(RPMFont.display(15))
                                    .foregroundStyle(RPMInk.white(0xD9 / 255))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .measure { textHeight = $0.height }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(textHeight, textRoom(screen.size.height)))

                    HStack(spacing: 10) {
                        Button(Loc.get("About_Close"), action: onClose)
                            .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))

                        Button(Loc.get("TrackInfo_ReadOnWikipedia")) {
                            if let url = URL(string: reading.article.url) { openUrl(url) }
                        }
                        .buttonStyle(RPMGlassButton(.primary, radius: 10, height: 42, size: 14))
                    }

                    // The licence the text is shared under, which CC BY-SA asks a reuse to name and
                    // link to. Small, under the keys, at the right.
                    Button(Loc.get("Wikipedia_Licence")) {
                        openUrl(Self.licence)
                    }
                    .buttonStyle(.plain)
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x80 / 255))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHint(Loc.get("Wikipedia_LicenceTip"))
                }
                .padding(18)
                .frame(width: 330)
                .rpmGlassCard(radius: 18)
            }
            .frame(width: screen.size.width, height: screen.size.height)
        }
    }

    /// How tall the text may be before it scrolls: the screen, less the card's heading, keys, the
    /// licence line and padding, and a margin above and below the card.
    private func textRoom(_ screen: CGFloat) -> CGFloat {
        max(160, screen - 280)
    }

    /// Wikipedia's text licence.
    private static let licence = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!
}

extension View {
    /// Puts ``AboutSheet`` over the page while `reading` holds something, and clears it on Close or a
    /// tap outside the card. Laid over the page the way the review popup is, fading in and out.
    func aboutSheet(_ reading: Binding<AboutReading?>) -> some View {
        overlay {
            if let shown = reading.wrappedValue {
                AboutSheet(reading: shown) { reading.wrappedValue = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: reading.wrappedValue?.id)
    }

    /// Hands this view's size to `told` when it is first laid out and whenever it changes.
    fileprivate func measure(_ told: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { box in
                Color.clear.onChange(of: box.size, initial: true) { _, now in told(now) }
            }
        }
    }
}
