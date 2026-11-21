import SwiftUI
import RPMKit

/// The settings card that chooses the language of the Wikipedia texts on the artist and album
/// pages: the phone's own language first, then the languages offered (``ArticleLanguages``), each
/// named in itself, as a language picker names them.
///
/// It writes the choice to the user defaults. The app reads the same key and tells its article
/// store, so the next page opened reads the new language. A page already open keeps its text.
///
/// It has the shape of every card on the settings page: the glyph and the kicker, then the
/// value. It is a view of its own, so the page only places it.
struct ArticleLanguageCard: View {
    @AppStorage(ArticleLanguages.key) private var chosen = ""

    /// The phone's own language, named in itself, in the first choice's words.
    private var phone: String {
        Loc.get("Settings_ArticleLanguagePhone",
                ArticleLanguages.name(of: ArticleLanguages.phoneLanguage(Locale.preferredLanguages)))
    }

    /// What the menu shows while it is closed. A code this build does not offer reads as the
    /// phone's language, which is what the pages then read too.
    private var shown: String {
        ArticleLanguages.offered.contains(chosen) ? ArticleLanguages.name(of: chosen) : phone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Glyph.globe)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x66 / 255))

                Text(Loc.get("Settings_ArticleLanguage")).rpmKicker()
            }

            Menu {
                Picker(Loc.get("Settings_ArticleLanguage"), selection: $chosen) {
                    Text(phone).tag("")
                    ForEach(ArticleLanguages.offered, id: \.self) { code in
                        Text(ArticleLanguages.name(of: code)).tag(code)
                    }
                }
            } label: {
                closed
            }
            .onChange(of: chosen) { _, _ in Haptics.pick() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .rpmSection()
    }

    /// The menu while it is closed: the choice in a dark field, with the up-down mark that shows it
    /// opens. The same field as the other menus on the settings page.
    private var closed: some View {
        HStack {
            Text(shown)
                .font(RPMFont.display(15))
            Spacer()
            Text(Glyph.sort).font(RPMFont.icon(11))
        }
        .foregroundStyle(RPMInk.white(0xF0 / 255))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            let well = RoundedRectangle(cornerRadius: 8, style: .continuous)
            well.fill(RPMInk.white(0x14 / 255))
                .overlay { well.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
        }
    }
}
