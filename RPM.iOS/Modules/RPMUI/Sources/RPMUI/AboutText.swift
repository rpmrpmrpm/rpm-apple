import SwiftUI
import UIKit
import RPMKit
import RPMLibrary

/// The look of Wikipedia text on a page: the font, the colour and the space between lines.
/// ``CentredAboutText`` uses them, and so does the mood list's sentence on the playlist page, so the
/// two pages look the same.
enum AboutText {
    static let font = RPMFont.display(14)
    static let ink = RPMInk.white(0xB3 / 255)

    /// The space between lines. SwiftUI adds it between lines only, not after the last one, so the
    /// bottom of the text is the bottom of the last line.
    static let lineSpacing: CGFloat = 7
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
/// **One step also means one layout.** A List row whose height changes in two layouts one frame
/// apart is drawn out of place for a frame or two: the sleeve over the text moves up or down, and so
/// does everything under it, and then all of it goes back. The text is cut for the width it stands
/// in, so its first layout must already have that width: see `column`.
struct CentredAboutText: View {
    let article: EncyclopediaArticle

    /// Words before the text, dimmer than it, that say what it is: "About the album" on a record's
    /// page. They are part of the first line and are measured with the text.
    let lead: String?

    /// Read more and Read less in small capitals, as the record's page has them.
    let capitalKeys: Bool

    /// Whether the text arrived after the page was drawn. It then comes in from the top as it fades
    /// in, opening down over the time Read more takes, as on the Android phone. The row it stands in
    /// still grows in one step, for the reason above: what is under it moves down at once. Text that
    /// is there on the first frame (read before, and kept) only fades in.
    let arrives: Bool

    /// - Parameter column: the width of the column the text stands in, which the page measures
    ///   before the text arrives (``SwiftUI/View/measuresWidth(into:)``). The text is cut for it on
    ///   its first layout. The text also measures itself and is cut again if the two differ, so a
    ///   wrong column costs the movement described above, never a wrong cut.
    init(article: EncyclopediaArticle, column: CGFloat, lead: String? = nil,
         capitalKeys: Bool = false, arrives: Bool = false) {
        self.article = article
        self.lead = lead
        self.capitalKeys = capitalKeys
        self.arrives = arrives
        _width = State(initialValue: column)
    }

    private static let lines = 3

    /// The keys' ink: brighter than the text, so they read as something to press.
    private static let keyInk = RPMInk.white(0xF0 / 255)

    /// The lead-in words' ink: dimmer than the text.
    private static let leadInk = RPMInk.white(0x80 / 255)

    /// What stands between the last word and the key: four spaces that do not break.
    private static let gap = String(repeating: "\u{00A0}", count: 4)

    /// Between the lead-in words and the text: a colon. No dashes in text the user reads.
    private static let leadGap = ": "

    /// The width the text is laid out in: the page's column at first, then what the text measures.
    /// Nothing is drawn while it is zero (see `body`).
    @State private var width: CGFloat

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
        ZStack(alignment: .top) {
            // **Nothing is drawn until the width is known.** The width decides where the text is
            // cut and whether the credit stands under it, so text drawn without it is drawn again
            // one frame later at another height. Only a page that has not measured its column yet
            // gets here, on its own first frame.
            if let folded = Self.cut(words, key: keyWord("Rpm_About_ReadMore"), keySize: keySize,
                                     width: width, size: size) {
                laidOut(folded)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .measuresWidth(into: $width)
    }

    /// The text cut for the width it is laid out in, with the key or the credit.
    private func laidOut(_ folded: Cut) -> some View {
        let fits = !folded.clipped
        let unfolded = open && !fits

        return VStack(spacing: 10) {
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
    ///
    /// Nil while the width is not known. Without a width there is no right answer: "it fits" puts the
    /// credit under the text for one frame, and "it is cut" takes it away for one.
    static func cut(_ words: String, key: String, keySize: CGFloat = 14, width: CGFloat,
                    size: DynamicTypeSize) -> Cut? {
        guard width > 0 else { return nil }

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

extension View {
    /// Writes this view's width to `width` when it is first laid out and whenever it changes. A page
    /// puts it on the column that ``CentredAboutText`` stands in, so the width is known before the text
    /// arrives. It is measured from the background, where it takes no part in the layout.
    func measuresWidth(into width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { box in
                Color.clear.onChange(of: box.size.width, initial: true) { _, now in
                    if width.wrappedValue != now { width.wrappedValue = now }
                }
            }
        }
    }
}
