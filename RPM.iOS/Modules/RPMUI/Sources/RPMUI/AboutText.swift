import SwiftUI
import UIKit
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

/// What Wikipedia says about an artist or a record, centred: its first paragraph, folded to three
/// lines with "Read more" in bold at the end of the third line when it is longer than that.
///
/// **The text stops at a whole word, and "Read more" ends the line.** The text is cut at the last
/// word that leaves room for the key on the third line (``cut(_:key:keySize:width:size:)``). The key
/// is joined to the last word with spaces that do not break, so it never starts a line of its own.
///
/// **A tap unfolds it in place**, with "Read less" at its end in the same style to fold it again, and
/// Wikipedia's credit under it (``WikipediaCredit``). A paragraph short enough to show whole has the
/// credit under it from the start. Only the first paragraph is shown; the rest is on Wikipedia.
///
/// **The row grows in one step and the new text fades in.** Both pages are Lists, and a List row that
/// changes height under an animation slides everything in it up and back down (see ``AboutRead``). So
/// the change of height is not animated, and the fade runs in a transaction of its own after it.
///
/// - `lead`: words before the text, dimmer than it, that say what it is: "About the album" on a
///   record's page. They are part of the first line and are measured with the text.
/// - `capitalKeys`: Read more and Read less in small capitals, as the record's page has them.
struct CentredAboutText: View {
    let article: EncyclopediaArticle
    var lead: String? = nil
    var capitalKeys = false

    /// Whether the text arrived after the page was drawn. It then comes in from the top as it fades
    /// in, opening down over the time Read more takes, as on the Android phone. The row it stands in
    /// still grows in one step, for the reason above: what is under it moves down at once. Text that
    /// is there on the first frame (read before, and kept) only fades in.
    var arrives = false

    private static let lines = 3

    /// The keys' ink: brighter than the text, so they read as something to press.
    private static let keyInk = RPMInk.white(0xF0 / 255)

    /// The lead-in words' ink: dimmer than the text.
    private static let leadInk = RPMInk.white(0x80 / 255)

    /// What stands between the last word and the key: four spaces that do not break.
    private static let gap = String(repeating: "\u{00A0}", count: 4)

    /// Between the lead-in words and the text.
    private static let leadGap = " \u{2013} "

    /// The width the text is laid out in. Zero until the first layout.
    @State private var width: CGFloat = 0

    /// The reader's text size. ``RPMFont`` faces grow with it, so the cut is measured at it too.
    @Environment(\.dynamicTypeSize) private var size

    /// Whether the paragraph is unfolded.
    @State private var open = false

    /// How far the text shown has faded in: on the first appearance, and after every fold.
    @State private var shown: Double = 0

    /// How far down the text has come in, when it arrives late (``arrives``).
    @State private var reveal: CGFloat = 0

    private var prefix: String { lead.map { $0 + Self.leadGap } ?? "" }

    /// The first paragraph, after the lead-in words.
    private var words: String { prefix + (article.paragraphs.first { !$0.isEmpty } ?? "") }

    private func keyWord(_ key: String) -> String {
        (capitalKeys ? Loc.get(key).uppercased() : Loc.get(key)).replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// The keys' size: the text's, or two points smaller in capitals, which read larger.
    private var keySize: CGFloat { capitalKeys ? 12 : 14 }

    var body: some View {
        let folded = Self.cut(words, key: keyWord("Rpm_About_ReadMore"), keySize: keySize, width: width, size: size)
        let fits = !folded.clipped
        let unfolded = open && !fits

        VStack(spacing: 10) {
            Button {
                guard !fits else { return }
                // The row's height changes here, with no animation; then the text fades in.
                open.toggle()
                shown = 0
                Task { @MainActor in withAnimation(.easeOut(duration: 0.32)) { shown = 1 } }
            } label: {
                Group {
                    if unfolded {
                        written(words, key: keyWord("Rpm_About_ReadLess"))
                    } else {
                        written(folded.text, key: folded.clipped ? keyWord("Rpm_About_ReadMore") : nil)
                            .lineLimit(Self.lines)
                    }
                }
                .font(AboutText.font)
                .lineSpacing(AboutText.lineSpacing)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(fits ? "" : Loc.get(unfolded ? "Rpm_About_ReadLess" : "Rpm_About_ReadMore"))

            if unfolded || fits {
                WikipediaCredit(article: article)
            }
        }
        .background {
            GeometryReader { box in
                Color.clear.onChange(of: box.size.width, initial: true) { _, now in width = now }
            }
        }
        .mask(alignment: .top) {
            Rectangle().scaleEffect(x: 1, y: arrives ? reveal : 1, anchor: .top)
        }
        .opacity(shown)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { shown = 1 }
            withAnimation(.easeInOut(duration: 0.32)) { reveal = 1 }
        }
    }

    /// The words with the lead-in dimmer, and the key after them in bold where there is one.
    private func written(_ said: String, key: String?) -> Text {
        let split = said.hasPrefix(prefix) ? prefix.count : 0
        let head = String(said.prefix(split))
        let rest = String(said.dropFirst(split))

        var text = Text(head).foregroundStyle(Self.leadInk) + Text(rest).foregroundStyle(AboutText.ink)
        if let key {
            text = text
                + Text(Self.gap)
                + Text(key).font(RPMFont.displayBold(keySize)).kerning(capitalKeys ? 0.6 : 0)
                    .foregroundStyle(Self.keyInk)
        }
        return text
    }

    // ── where the text is cut ──

    /// The text to show, and whether it was cut (and so ends with the key).
    struct Cut: Equatable {
        let text: String
        let clipped: Bool
    }

    /// The longest run of whole words that fits in three lines with the key after it, or all of the
    /// text when it fits in three lines by itself.
    ///
    /// It is measured with TextKit, in the faces and size that SwiftUI draws. A `Font.custom` face
    /// grows with the reader's text size as the body style does, so the measuring fonts are scaled
    /// with `UIFontMetrics` for the body style at `size`. The width is measured a little narrower
    /// than it is, so that a rounding difference between TextKit and SwiftUI cannot push the key
    /// onto a fourth line, which `lineLimit` would cut off.
    static func cut(_ words: String, key: String, keySize: CGFloat = 14, width: CGFloat,
                    size: DynamicTypeSize) -> Cut {
        guard width > 0 else { return Cut(text: words, clipped: false) }

        let room = width - 2
        let body = scaled(RPMFont.mediumFace, points: 14, size: size)
        let bold = scaled(RPMFont.boldFace, points: keySize, size: size)

        if lineCount(NSAttributedString(string: words, attributes: [.font: body]), width: room) <= lines {
            return Cut(text: words, clipped: false)
        }

        // Three lines never hold this much on a phone, at any text size. Only the start of a long
        // article is searched.
        let start = String(words.prefix(600))

        var ends: [String.Index] = []
        start.enumerateSubstrings(in: start.startIndex..., options: [.byWords, .substringNotRequired]) {
            _, range, _, _ in ends.append(range.upperBound)
        }

        func fits(_ end: String.Index) -> Bool {
            let line = NSMutableAttributedString(string: String(start[..<end]) + gap,
                                                 attributes: [.font: body])
            line.append(NSAttributedString(string: key, attributes: [.font: bold]))
            return lineCount(line, width: room) <= lines
        }

        var low = 0, high = ends.count - 1, best: Int?
        while low <= high {
            let middle = (low + high) / 2
            if fits(ends[middle]) {
                best = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        return Cut(text: best.map { String(start[..<ends[$0]]) } ?? "", clipped: true)
    }

    /// A face at the text's size, grown or shrunk as SwiftUI grows a custom face at `size`. The
    /// system face stands in where the face did not load, as ``RPMFont`` does.
    private static func scaled(_ name: String?, points: CGFloat, size: DynamicTypeSize) -> UIFont {
        let base = name.flatMap { UIFont(name: $0, size: points) } ?? .systemFont(ofSize: points)
        let traits = UITraitCollection(preferredContentSizeCategory: category(size))
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
    }

    private static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    /// How many lines `text` takes at `width`.
    private static func lineCount(_ text: NSAttributedString, width: CGFloat) -> Int {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let box = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        box.lineFragmentPadding = 0
        layout.addTextContainer(box)
        storage.addLayoutManager(layout)

        var count = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: box)) { _, _, _, _, _ in
            count += 1
        }
        return count
    }
}

/// Wikipedia's credit, under text of theirs shown whole: a link to the article and the licence it is
/// shared under, which CC BY-SA asks a reuse to name and link to.
struct WikipediaCredit: View {
    let article: EncyclopediaArticle

    @Environment(\.openURL) private var openUrl

    private static let licence = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!

    var body: some View {
        HStack(spacing: 6) {
            Button(Loc.get("TrackInfo_ReadOnWikipedia")) {
                if let url = URL(string: article.url) { openUrl(url) }
            }
            Text("\u{00B7}")
            Button(Loc.get("Wikipedia_Licence")) { openUrl(Self.licence) }
                .accessibilityHint(Loc.get("Wikipedia_LicenceTip"))
        }
        .buttonStyle(.plain)
        .font(RPMFont.display(11))
        .foregroundStyle(RPMInk.white(0x80 / 255))
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
