import SwiftUI
import RPMKit
import RPMArt
import RPMAudio

/// The account, and all the app settings that are choices and not records.
///
/// Ported from `RPM.Mobile/Presentation/ProfilePage.xaml`. It is a tab and not a gear button in a
/// corner, because it holds more than settings: how much cloud storage is used, the plan of the
/// account, and the way to sign out. Users look for these, so they should be easy to find.
///
/// Every card has the same shape: a glyph and a kicker, then the current value, then the
/// actions.
///
/// One card of the desktop app is not here: sharing is arranged between two computers on one
/// network, and a phone cannot be either of them. It will be added together with the feature it
/// controls.
public struct ProfilePage: View {
    private let name: String
    private let email: String
    private let quota: CloudQuota?
    private let onWifi: Binding<Int>
    private let onCellular: Binding<Int>

    /// The bit rate that downloads ask for, on any network.
    private let onDownload: Binding<Int>

    /// Whether records are levelled (volume levelling), and by album or by track.
    private let levelling: Binding<NormalizeMode>

    /// Whether records marked as classical are levelled too.
    private let levelsClassical: Binding<Bool>

    /// The state of the network connection. This screen reads it for one purpose: to check
    /// whether the two menu values are the rates that the player will really ask for. **There is
    /// no default.** A screen that assumed an unrestricted network would show a setting of 320
    /// to a user whose phone is streaming at 128, without any explanation.
    private let reach: Reach

    private let cached: Int64

    /// How many albums are downloaded to this phone, and what they take.
    private let downloaded: (albums: Int, bytes: Int64)
    private let onDownloads: () -> Void

    private let version: String
    private let onClearCache: () -> Void
    private let onSignOut: () -> Void

    /// Deletes the account on the server and signs out. Returns nil when done, and an error
    /// message when it failed.
    private let onDeleteAccount: () async -> String?
    private let onSupport: () -> Void

    /// The Send crash reports switch.
    private let crashReports: Binding<Bool>

    /// Opens Send feedback. Nil hides the key: only a TestFlight build offers it (`ReportScope`).
    private let onFeedback: (() -> Void)?

    /// Whether the delete-account panel is shown.
    @State private var deletingAccount = false

    /// Whether the acknowledgements are shown.
    @State private var credits = false

    /// The id of the chosen backdrop. The background on every page reads the same key, so writing
    /// it here changes the whole app and not only this card. See ``VinylGround``.
    @AppStorage(Backdrop.key) private var backdropId = ""

    public init(name: String, email: String, quota: CloudQuota?,
                onWifi: Binding<Int>, onCellular: Binding<Int>, onDownload: Binding<Int>,
                levelling: Binding<NormalizeMode>,
                levelsClassical: Binding<Bool>,
                reach: Reach,
                cached: Int64,
                downloaded: (albums: Int, bytes: Int64),
                onDownloads: @escaping () -> Void,
                version: String,
                onClearCache: @escaping () -> Void,
                onSignOut: @escaping () -> Void,
                onDeleteAccount: @escaping () async -> String?,
                onSupport: @escaping () -> Void,
                crashReports: Binding<Bool>,
                onFeedback: (() -> Void)?) {
        self.name = name
        self.email = email
        self.quota = quota
        self.onWifi = onWifi
        self.onCellular = onCellular
        self.onDownload = onDownload
        self.levelling = levelling
        self.levelsClassical = levelsClassical
        self.reach = reach
        self.cached = cached
        self.downloaded = downloaded
        self.onDownloads = onDownloads
        self.version = version
        self.onClearCache = onClearCache
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        self.onSupport = onSupport
        self.crashReports = crashReports
        self.onFeedback = onFeedback
    }

    /// The bit rates that this account may choose between.
    ///
    /// It uses the quota that the storage meter already fetches, because the phone has no
    /// separate supporter service to ask. A nil quota means it is not known yet, and then the
    /// whole ladder is offered. Telling a supporter that they are on the free plan because a
    /// request timed out is the worse of the two possible mistakes.
    private var offer: AudioLadder.RateOffer {
        guard let quota else { return .unread }
        return .of(isSupporter: quota.supporter)
    }

    public var body: some View {
        // The header stays fixed over the scroll view, as in the desktop app. It is the name of
        // the page, and the user should not have to scroll back to see it. Every other page
        // here is built the same way.
        DissolvingScroll {
            VStack(alignment: .leading, spacing: 14) {
                account
                storage
                downloads
                plan
                backdrop
                playback
                loudness
                device
                about
            }
            .padding(.horizontal, RPMLayout.margin)
            .padding(.top, 4)
            .padding(.bottom, RPMLayout.foot)
        }
        .scrollIndicators(.hidden)
        .scrollsUnder { header }
        .background { VinylGround() }
        .overlay {
            if deletingAccount {
                DeleteAccountSheet(email: email, commit: onDeleteAccount,
                                   onClose: { deletingAccount = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: deletingAccount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PageTitle.subtitleGap) {
            PageTitle(Loc.get("Rpm_Tab_Profile"))

            Text(Loc.get("Rpm_Profile_Subtitle")).rpmKicker()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RPMLayout.margin)
        // No top padding: in the Uno phone app, SafeArea.Insets replaces the ten points that
        // its markup asks for, so its headers start at the safe area. See
        // `LibraryPage.header`.
        .padding(.bottom, 8)
    }

    // ── account ──

    private var account: some View {
        card(Glyph.profile, Loc.get("Rpm_Profile_Account")) {
            // No supporter badge here. It is shown in the Supporter card instead.
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? email : name)
                    .font(RPMFont.display(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !name.isEmpty {
                    Text(email)
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0x88 / 255))
                        .lineLimit(1)
                }
            }

            Text(Loc.get("Rpm_Profile_SignOutDetail"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))

            // One row: Sign out takes two thirds and Delete takes one third, so the action that
            // users need most is the larger key, and the destructive one is still on the card.
            // The app must make account deletion easy to find (App Store guideline 5.1.1(v)), so
            // it is not hidden. The panel it opens asks for the email address, so a tap on Delete
            // deletes nothing by itself.
            GeometryReader { row in
                let third = (row.size.width - Self.keysApart) / 3

                HStack(spacing: Self.keysApart) {
                    key(Loc.get("Login_SignOut"), stretches: true, action: onSignOut)
                        .frame(width: third * 2)

                    Button { deletingAccount = true } label: {
                        // One word, because a third of the row is too narrow for "Delete account" in
                        // English or in French. The card says what is deleted.
                        Text(Loc.get("Rpm_Profile_DeleteAccount"))
                            .foregroundStyle(RPMInk.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: Self.keyHeight,
                                                stretches: true, inset: 12, size: 13))
                    .frame(width: third)
                    .accessibilityLabel(Loc.get("Account_Delete"))
                }
            }
            .frame(height: Self.keyHeight)
        }
    }

    /// The space between two keys on one row.
    private static let keysApart: Double = 10

    // ── cloud storage ──

    private var storage: some View {
        card(Glyph.cloud, Loc.get("Cloud_Heading")) {
            if let quota {
                Text(said(quota))
                    .font(RPMFont.display(17))
                    .foregroundStyle(.white)

                if !quota.unlimited, quota.quotaBytes > 0 {
                    meter(Double(quota.usedBytes) / Double(quota.quotaBytes))
                }

                Text(quota.fileCount == 1 ? Loc.get("Rpm_Profile_TracksOne")
                                              : Loc.get("Rpm_Queue_Count", quota.fileCount))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x66 / 255))
            } else {
                Text(Loc.get("Rpm_Profile_QuotaUnknown"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
            }
        }
    }

    /// The usage bar. It uses the same white as the seek knob and the playing mark, on a dark
    /// track in the card's own tone.
    private func meter(_ full: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0x22 / 255))
                Capsule()
                    .fill(full > 0.9 ? RPMInk.red : RPMInk.white(0xE6 / 255))
                    .frame(width: geometry.size.width * min(1, max(0, full)))
            }
        }
        .frame(height: 4)
        .padding(.vertical, 2)
    }

    // ── on this phone ──

    /// The albums kept on the phone for listening offline, and the way to the list of them.
    private var downloads: some View {
        card(Glyph.download, Loc.get("Rpm_Downloads_Title")) {
            Text(downloaded.albums == 0
                 ? Loc.get("Rpm_Downloads_None")
                 : downloaded.albums == 1
                    ? Loc.get("Rpm_Downloads_SummaryOne", bytes(downloaded.bytes))
                    : Loc.get("Rpm_Downloads_Summary", downloaded.albums, bytes(downloaded.bytes)))
                .font(RPMFont.display(17))
                .foregroundStyle(.white)

            Text(Loc.get("Rpm_Downloads_Detail"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))

            key(Loc.get("Rpm_Downloads_Manage"), stretches: true, action: onDownloads)
        }
    }

    // ── supporter status ──

    /// The string for this account's standing: a closed beta tester, a paying supporter, or free.
    static func planKey(_ quota: CloudQuota, supporter: String, tester: String, free: String) -> String {
        quota.tester ? tester : quota.supporter ? supporter : free
    }

    /// Shows only this account's status. It is hidden until the quota has been read, so a request
    /// that timed out does not show "Not a supporter" to a supporter.
    @ViewBuilder
    private var plan: some View {
        if let quota {
            card(Glyph.heart, Loc.get("Rpm_Profile_Plan")) {
                VStack(alignment: .leading, spacing: 4) {
                    // A supporter gets the gold badge, which contains the word "Supporter". The free
                    // plan and a closed beta tester are named in cyan: a tester has the supporter
                    // features but does not pay, so does not wear the badge.
                    if quota.wearsMark {
                        SupporterMark()
                            .padding(.vertical, 2)
                    } else {
                        Text(Loc.get(quota.tester ? "Rpm_Profile_PlanTester" : "Rpm_Profile_PlanFree"))
                            .font(RPMFont.display(17))
                            .foregroundStyle(RPMInk.cyan)
                    }

                    Text(Loc.get(Self.planKey(quota, supporter: "Rpm_Profile_PlanSupporterDetail",
                                              tester: "Rpm_Profile_PlanTesterDetail",
                                              free: "Rpm_Profile_PlanFreeDetail")))
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0x88 / 255))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Loc.get(Self.planKey(quota, supporter: "Rpm_Profile_PlanSupporterThanks",
                                              tester: "Rpm_Profile_PlanTesterThanks",
                                              free: "Rpm_Profile_PlanFreeAppeal")))
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0xB3 / 255))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
        }
    }

    // ── how much of a track comes down ──

    /// Two settings for listening, not one. A user often wants the original quality at home and a
    /// lower quality on a train. A single setting would need to be changed often, and in practice
    /// it would often be wrong. A third setting is for downloads, which is a choice about space
    /// on the phone and not about the network.
    private var playback: some View {
        card(Glyph.speaker, Loc.get("Rpm_Profile_Playback")) {
            rate(Loc.get("Rpm_Profile_QualityWifi"), onWifi)
            rate(Loc.get("Rpm_Profile_QualityCellular"), onCellular)

            // The note is shown next to the settings, and only while it applies. Low Data Mode
            // overrides both menus. A menu that shows 320 while the stream is 128, with no
            // reason on the screen, looks like a setting that does nothing.
            if reach.isConstrained {
                Text(Loc.get("Rpm_Profile_QualityLowData"))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
            }

            // Under the two streaming menus and after the Low Data note, which is about
            // streaming only. A download asks for this rate on any network.
            rate(Loc.get("Rpm_Profile_QualityDownload"), onDownload)

            Text(Loc.get("Rpm_Profile_QualityDownloadDetail"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x88 / 255))

            // Directly under the menus, because a greyed-out control needs its reason next to it.
            if offer.capped {
                Text(Loc.get("Rpm_Profile_QualityCapped"))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))

                key(Loc.get("Cloud_BecomeSupporter"), stretches: true, action: onSupport)
            }

            Text(Loc.get("Rpm_Profile_QualityDetail"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
    }

    private func rate(_ label: String, _ chosen: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xB3 / 255))

            // A menu and not a segmented control: six steps across a phone would leave about
            // four characters for each, and the labels are words.
            Menu {
                Picker(label, selection: chosen) {
                    ForEach(offer.rungs, id: \.self) { rung in
                        Text(named(rung)).tag(rung)
                    }
                }
            } label: {
                closedMenu(named(offer.settles(on: chosen.wrappedValue)), dimmed: offer.capped)
            }
            // Shown but disabled. The one step that a free account has is still useful to see,
            // and a hidden control would make the user ask where it went.
            .disabled(offer.capped)
        }
    }

    private func named(_ rung: Int) -> String {
        rung == AudioLadder.original ? Loc.get("Rpm_Playback_Original")
                                     : Loc.get("Rpm_Profile_QualityKbps", rung)
    }

    /// How a menu on this screen looks while it is closed: the current choice in a dark field,
    /// with the up-down mark that shows it can be opened.
    private func closedMenu(_ text: String, dimmed: Bool) -> some View {
        HStack {
            Text(text)
                .font(RPMFont.display(15))
            Spacer()
            Text(Glyph.sort).font(RPMFont.icon(11))
        }
        .foregroundStyle(dimmed ? RPMInk.white(0x59 / 255) : RPMInk.white(0xF0 / 255))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            let well = RoundedRectangle(cornerRadius: 8, style: .continuous)
            well.fill(RPMInk.white(0x14 / 255))
                .overlay { well.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
        }
    }

    // ── how loud ──

    /// Volume levelling, with the three choices of the desktop app in the same order: off, match
    /// albums, match tracks. It is a card of its own and not a row in Playback, because Playback
    /// is about how much of a track is downloaded, and this is about how it sounds.
    ///
    /// "Level classical recordings too" is the same option as in the desktop app, and it reads
    /// the classical mark that the desktop app syncs. An album's own Always/Never setting is not
    /// here: it is kept in the desktop app's local library and never reaches the phone, so it
    /// would have no effect.
    private var loudness: some View {
        card(Glyph.levelling, Loc.get("Settings_Normalize")) {
            Menu {
                Picker(Loc.get("Settings_Normalize"), selection: levelling) {
                    ForEach(NormalizeMode.allCases, id: \.self) { mode in
                        Text(named(mode)).tag(mode)
                    }
                }
            } label: {
                closedMenu(named(levelling.wrappedValue), dimmed: false)
            }

            Text(Loc.get("Rpm_Profile_LevellingDetail"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .fixedSize(horizontal: false, vertical: true)

            // Hidden while levelling is off, as in the desktop app, because there is nothing to
            // level.
            if levelling.wrappedValue != .off {
                Toggle(isOn: levelsClassical) {
                    Text(Loc.get("Settings_NormalizeClassical"))
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0xB3 / 255))
                }
                .tint(RPMInk.white(0x88 / 255))

                Text(Loc.get("Settings_NormalizeClassicalHint"))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func named(_ mode: NormalizeMode) -> String {
        switch mode {
        case .off: Loc.get("Settings_NormalizeOff")
        case .album: Loc.get("Settings_NormalizeAlbum")
        case .track: Loc.get("Settings_NormalizeTrack")
        }
    }

    // ── what is on the phone itself ──

    private var device: some View {
        card(Glyph.phone, Loc.get("Rpm_Playback_FromPhone")) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.get("Rpm_Profile_ArtCache"))
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0xB3 / 255))

                    Text(bytes(cached))
                        .font(RPMFont.display(17))
                        .foregroundStyle(.white)
                }

                Spacer()

                key(Loc.get("Catalog_FanartClear"), stretches: false, action: onClearCache)
            }

            Text(Loc.get("Rpm_Profile_ArtCacheDetail"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
    }

    // ── about ──

    private var about: some View {
        card(Glyph.about, Loc.get("Rpm_Profile_About")) {
            Text(Loc.get("Rpm_Profile_Tagline"))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xB3 / 255))

            Text(Loc.get("Rpm_Profile_Version", version))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))

            // A sheet and not a push: this tab is not inside a `NavigationStack`, because a stack
            // paints its own opaque background over the app's background.
            key(Loc.get("About_Acknowledgements"), stretches: true) { credits = true }

            if let onFeedback {
                key(Loc.get("Shell_Feedback"), stretches: true, action: onFeedback)
            }

            Toggle(isOn: crashReports) {
                Text(Loc.get("Settings_CrashReports"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xB3 / 255))
            }
            .tint(RPMInk.white(0x88 / 255))

            Text(Loc.get("Settings_CrashReportsDesc"))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $credits) {
            AboutPage(version: version) { credits = false }
        }
    }

    // ── the app background ──

    /// The five built-in backdrops, as tiles.
    ///
    /// **A row of the real pictures**, as in the desktop app's settings. The supporter backdrop
    /// is shown to everybody and is not greyed out, so that users can see what it looks like.
    /// A tap on it without support opens the page that explains it.
    private var backdrop: some View {
        card(Glyph.picture, Loc.get("Settings_Background")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Backdrop.Choice.allCases, id: \.self) { choice in
                        tile(choice)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    /// The tile that is selected. It shows what is actually in use and not what is stored, so the
    /// gold tile cannot be selected while the app's own background is on the screen. See
    /// ``Backdrop/standing(stored:gold:)``.
    private var standing: Backdrop.Choice {
        Backdrop.standing(stored: backdropId, gold: SupporterGround.isGold)
    }

    /// A tile has the shape of the phone screen. It is small enough that five tiles and part of a
    /// sixth fit on a narrow screen, so the row shows that there is more to the right.
    private static let tileWide: Double = 62
    private static let tileTall: Double = 116

    private func tile(_ choice: Backdrop.Choice) -> some View {
        let picked = choice == standing
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return Button {
            Haptics.pick()

            // The check uses the same value that the background reads (`SupporterGround.isGold`),
            // not the quota that this screen shows. The two are known at different times. A tile
            // that was selected for a picture that the background would not show would be wrong.
            if choice.isSupporters && !SupporterGround.isGold {
                onSupport()
            } else {
                backdropId = choice.rawValue
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    shape.fill(Color.black.opacity(0x22 / 255))

                    BackdropTile(choice: choice, width: Self.tileWide, height: Self.tileTall)
                        .clipShape(shape)

                    if picked {
                        // On the picture and not beside the name: the tile is the thing that was
                        // chosen, and a mark under it would look like a caption.
                        shape.fill(Color.black.opacity(0.45))

                        Text(Glyph.check)
                            .font(RPMFont.icon(14))
                            .foregroundStyle(.white)
                    } else if choice.isSupporters && !SupporterGround.isGold {
                        Text(Glyph.heart)
                            .font(RPMFont.icon(11))
                            .foregroundStyle(RPMInk.white(0xCC / 255))
                            .padding(4)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .bottomTrailing)
                            .padding(5)
                    }
                }
                .frame(width: Self.tileWide, height: Self.tileTall)
                .overlay {
                    // The selected tile has a white edge, and the others have the card's own border,
                    // which is a gradient. These are two separate shapes and not one with a
                    // ternary, because the two strokes use different kinds of paint.
                    if picked {
                        shape.strokeBorder(RPMInk.white(0xDD / 255), lineWidth: 1.5)
                    } else {
                        shape.strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                    }
                }

                Text(Loc.get(choice.nameKey))
                    .font(.system(size: 11, weight: picked ? .semibold : .regular))
                    .foregroundStyle(picked ? .white : Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: Self.tileWide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.get(choice.nameKey))
    }

    // ── the shape of every card ──

    private func card<Content: View>(
        _ glyph: String, _ kicker: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // The glyph has the same faint white as the kicker beside it and a small size, so
                // it works as a quiet mark and does not draw attention as an icon would.
                Text(glyph)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x66 / 255))

                Text(kicker).rpmKicker()
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .rpmSection()
    }

    /// The keys on this screen are smaller than the app's standard glass button. None of them is
    /// the main action of a screen, as "Play album" is. They are inside cards, next to the text
    /// they belong to, and a full-height key there would be too prominent.
    private func key(_ title: String, stretches: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: Self.keyHeight,
                                        stretches: stretches, inset: 16, size: 13))
    }

    /// The height of a key on this screen.
    private static let keyHeight: Double = 34

    // ── the words ──

    private func said(_ quota: CloudQuota) -> String {
        guard !quota.unlimited, quota.quotaBytes > 0 else {
            return Loc.get("Cloud_UsageUnlimited", bytes(quota.usedBytes))
        }

        let full = Double(quota.usedBytes) / Double(quota.quotaBytes)
        let key = full > 0.95 ? "Cloud_UsageFull" : full > 0.8 ? "Cloud_UsageAlmostFull" : "Cloud_Usage"

        return Loc.get(key, bytes(quota.usedBytes), bytes(quota.quotaBytes))
    }

    private func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = count < 1_000_000 ? [.useKB] : [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: count)
    }
}
