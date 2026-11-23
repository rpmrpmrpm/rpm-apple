import SwiftUI
import RPMKit

/// The settings card that chooses the app's language: the phone's own first, then the five
/// languages of the app, each named in itself.
///
/// A new choice shows at once: the app shows itself again in the new language (see `RPMApp`).
struct AppLanguageCard: View {
    var body: some View {
        SettingsCardFrame(Glyph.globe, Loc.get("Settings_AppLanguage")) {
            AppLanguageMenu()
        }
    }
}

/// The menu of the app's languages, closed to the choice in a dark field, as the other menus on
/// the settings page. The welcome's language step uses it too.
struct AppLanguageMenu: View {
    @AppStorage(Loc.chosenKey) private var chosen = ""

    var body: some View {
        Menu {
            Picker(Loc.get("Settings_AppLanguage"), selection: choice) {
                Text(Loc.get("Settings_AppLanguagePhone")).tag("")
                ForEach(Loc.offered, id: \.self) { code in
                    Text(Loc.name(of: code)).tag(code)
                }
            }
        } label: {
            HStack {
                Text(Loc.offered.contains(chosen) ? Loc.name(of: chosen) : Loc.get("Settings_AppLanguagePhone"))
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

    /// Writes through ``Loc/choose(_:)``, which also tells the system.
    private var choice: Binding<String> {
        Binding(get: { Loc.offered.contains(chosen) ? chosen : "" },
                set: { code in
                    guard code != chosen else { return }
                    Haptics.pick()
                    Loc.choose(code)
                })
    }
}
