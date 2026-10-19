import SwiftUI
import RPMKit
import RPMAudio
import RPMLibrary

/// The settings, in the same sections as the Android TV app: General (the screensaver delay),
/// Profile (the account and signing out), Display (the picture, the pages' background and the
/// performance statistics), Sound (the streaming quality and volume levelling) and Visualisation
/// (the layout that the player opens with). The Select button on a row moves it to its next
/// value. The language is set by the Apple TV itself.
struct SettingsView: View {
    @Environment(TVModel.self) private var model

    /// Whether Sign out has been pressed once. A second press signs out, so one accidental press
    /// does not.
    @State private var signOutAsked = false

    /// The albums screen's sort order. The screen stores it between launches, and this setting
    /// changes the stored value.
    @AppStorage("tv.wall.order") private var orderName = AlbumOrdering.artist.rawValue

    var body: some View {
        let settings = model.settings
        let on = Loc.get("Viz_SettingOn"), off = Loc.get("Viz_SettingOff")
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 44) {
                SettingsSection(title: Loc.get("Tv_SettingsGeneral"), symbol: "gearshape") {
                    SettingRow(label: Loc.get("Tv_SettingsAlbumView"),
                               value: settings.albumCarousel ? Loc.get("Tv_AlbumViewCarousel") : Loc.get("Tv_AlbumViewGrid")) {
                        settings.switchAlbumView()
                    }
                    SettingRow(label: Loc.get("Tv_SettingsAlbumSort"),
                               value: Wall.label(AlbumOrdering(rawValue: orderName) ?? .artist)) {
                        let all = AlbumOrdering.allCases
                        let now = AlbumOrdering(rawValue: orderName) ?? .artist
                        orderName = all[((all.firstIndex(of: now) ?? 0) + 1) % all.count].rawValue
                    }
                    SettingRow(label: Loc.get("Tv_SettingsScreensaver"), value: wait(settings.screensaverMinutes)) {
                        settings.nextScreensaver()
                    }
                }

                SettingsSection(title: Loc.get("Settings_Profile"), symbol: "person") {
                    AccountBlock()
                    SettingRow(label: Loc.get("Login_SignOut"),
                               value: signOutAsked ? Loc.get("Tv_SignOutConfirm") : "") {
                        if signOutAsked {
                            Task { await model.signOut() }
                        } else {
                            signOutAsked = true
                        }
                    }
                }

                SettingsSection(title: Loc.get("Settings_Display"), symbol: "tv") {
                    SettingRow(label: Loc.get("Tv_SettingsPicture"), value: picture(settings.picture)) {
                        settings.nextPicture()
                    }
                    SettingRow(label: Loc.get("Settings_Background"), value: background(settings.background)) {
                        settings.nextBackground()
                    }
                    SettingRow(label: Loc.get("Tv_SettingsShowStats"), value: settings.showStats ? on : off) {
                        settings.switchStats()
                    }
                }

                SettingsSection(title: Loc.get("Settings_Sound"), symbol: "speaker.wave.2") {
                    SettingRow(label: Loc.get("Atv_SettingsQuality"),
                               value: quality(model.offer.settles(on: settings.kilobits))) {
                        model.nextQuality()
                    }
                    SettingRow(label: Loc.get("Settings_Normalize"), value: levelling(settings.levelling)) {
                        model.nextLevelling()
                    }
                    // Shown only when levelling is on. When it is off, nothing is levelled, whether
                    // it is classical or not.
                    if settings.levelling != .off {
                        SettingRow(label: Loc.get("Settings_NormalizeClassical"),
                                   value: settings.levelsClassical ? on : off) {
                            model.switchLevelsClassical()
                        }
                    }
                }

                SettingsSection(title: Loc.get("Tv_SettingsPlayer"), symbol: "play") {
                    // For supporters only, as on the desktop. The row is always shown so that it can
                    // be found. For other users it shows the supporter title and does nothing. The
                    // stored setting is kept.
                    SettingRow(label: Loc.get("Tv_SettingsKaraoke"),
                               value: model.isSupporter != true ? Loc.get("Supporters_Title")
                                    : settings.karaoke ? on : off) {
                        if model.isSupporter == true { settings.switchKaraoke() }
                    }
                }

                SettingsSection(title: Loc.get("Tv_SettingsVisualisation"), symbol: "waveform") {
                    SettingRow(label: Loc.get("Tv_SettingsDefaultLayout"), value: layout(settings.defaultView)) {
                        settings.nextDefaultView()
                    }
                }
            }
            .frame(width: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, Size.top)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
    }

    private func picture(_ look: PictureLook) -> String {
        switch look {
        case .standard: Loc.get("Tv_PictureStandard")
        case .softer: Loc.get("Tv_PictureSofter")
        case .muted: Loc.get("Tv_PictureMuted")
        }
    }

    private func background(_ background: PageBackground) -> String {
        switch background {
        case .still: Loc.get("Settings_BackgroundDefault")
        case .pegasus: Loc.get("Settings_BackgroundPegasus")
        case .dark: Loc.get("Tv_BackgroundDark")
        case .moving: Loc.get("Tv_BackgroundMoving")
        }
    }

    private func layout(_ view: PlayerView) -> String {
        switch view {
        case .spread: Loc.get("Viz_LayoutFull")
        case .centred: Loc.get("Viz_LayoutCompact")
        case .room: Loc.get("Viz_LayoutVisuals")
        }
    }

    private func quality(_ kilobits: Int) -> String {
        kilobits == AudioLadder.original ? Loc.get("Rpm_Playback_Original")
                                         : Loc.get("Rpm_Profile_QualityKbps", String(kilobits))
    }

    private func levelling(_ mode: NormalizeMode) -> String {
        switch mode {
        case .off: Loc.get("Settings_NormalizeOff")
        case .album: Loc.get("Settings_NormalizeAlbum")
        case .track: Loc.get("Settings_NormalizeTrack")
        }
    }

    private func wait(_ minutes: Int) -> String {
        switch minutes {
        case 0: Loc.get("Viz_SettingOff")
        case 1: Loc.get("Tv_SettingsAfterMinute")
        default: Loc.get("Tv_SettingsAfterMinutes", String(minutes))
        }
    }
}

/// One section of the settings: its symbol and name, then its rows.
private struct SettingsSection<Rows: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.tv(Size.heading, .semibold))
                .foregroundStyle(Ink.card)
                .padding(.leading, RowStyle.inset)
            VStack(spacing: 6) { rows() }
        }
        .focusSection()
    }
}

/// One setting: its name on the left, its value on the right.
private struct SettingRow: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.tv(Size.row, .semibold))
                    .foregroundStyle(Ink.words)
                Spacer(minLength: 40)
                Text(value)
                    .font(.tv(Size.row))
                    .foregroundStyle(Color.white.opacity(0xCC / 255))
            }
        }
        .buttonStyle(RowStyle())
        .remembered("setting:" + label)
    }
}

/// The account, as the phone's profile shows it: who is signed in, the supporter status, the cloud
/// storage used and the version of this build. The user can only read these lines, so none of
/// them takes the focus.
private struct AccountBlock: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        let session = model.session
        let own = session.shelfRows.first(where: \.isOwn)?.face
        let who = session.who
        let name = own?.isKnown == true ? own!.displayName : (who?.displayName ?? "")
        let email = who?.email ?? ""

        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                InfoRow(label: name.isEmpty ? email : name, value: name.isEmpty ? "" : email)
                if let quota = session.quota {
                    // A supporter sees the supporter badge, which contains the word "Supporter",
                    // as in the phone's and the desktop's profile. A free account sees the name of
                    // the free plan.
                    if quota.unlimited {
                        InfoRow(label: Loc.get("Rpm_Profile_Plan")) { SupporterMark() }
                    } else {
                        InfoRow(label: Loc.get("Rpm_Profile_Plan"), value: Loc.get("Rpm_Profile_PlanFree"))
                    }
                    InfoRow(label: Loc.get("Cloud_Heading"), value: Self.storage(quota))
                }
                InfoRow(label: Loc.get("Rpm_Profile_Version", Self.version), value: "")
            }
        }
        .padding(.leading, RowStyle.inset)
    }

    /// The storage line, for example "12 GB of 100 GB used (almost full)". It has the same text as
    /// the phone's storage card.
    static func storage(_ quota: CloudQuota) -> String {
        guard !quota.unlimited, quota.quotaBytes > 0 else {
            return Loc.get("Cloud_UsageUnlimited", bytes(quota.usedBytes))
        }
        let full = Double(quota.usedBytes) / Double(quota.quotaBytes)
        let key = full > 0.95 ? "Cloud_UsageFull" : full > 0.8 ? "Cloud_UsageAlmostFull" : "Cloud_Usage"
        return Loc.get(key, bytes(quota.usedBytes), bytes(quota.quotaBytes))
    }

    private static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = count < 1_000_000 ? [.useKB] : [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: count)
    }

    /// The version and build number from the app bundle, for example "1.0 (12)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// One line of the account: the label on the left and the value on the right. It has the same
/// height and inset as a setting row.
private struct InfoRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    init(label: String, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.tv(Size.row))
                .foregroundStyle(Ink.words)
                .lineLimit(1)
            Spacer(minLength: 40)
            value()
        }
        .padding(.vertical, 10)
        .padding(.trailing, RowStyle.inset)
    }
}

extension InfoRow where Value == InfoWords {
    /// A value in words.
    init(label: String, value: String) {
        self.init(label: label) { InfoWords(text: value) }
    }
}

/// An account line's value as text.
private struct InfoWords: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.tv(Size.row))
            .foregroundStyle(Color.white.opacity(0xCC / 255))
            .lineLimit(1)
    }
}
