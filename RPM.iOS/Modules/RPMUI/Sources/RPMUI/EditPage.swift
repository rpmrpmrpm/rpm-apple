import SwiftUI
import PhotosUI
import UIKit
import Observation
import RPMKit

/// What the reader has changed on the edit page and not saved yet, beside what the page showed when it opened.
/// Nothing reaches the server until the app saves it. It is the Android app's `PageEdit`.
@MainActor
@Observable
public final class ProfileEdit {
    public let nameAtStart: String
    public var name: String

    /// A new photo, ready to send; nil to keep the one there is.
    public var photo: Data?
    public var dropPhoto = false

    /// A new banner photo, ready to send; nil to keep the one there is.
    public var banner: Data?
    public var dropBanner = false

    /// Whether the banner is the playing artist's photo.
    public let followsAtStart: Bool
    public var follows: Bool

    public let groundAtStart: RPMPageGround
    public var ground: RPMPageGround

    public let badgeAtStart: String
    public var badge: String
    public let colourAtStart: String
    public var colour: String

    /// - Parameter isSample: the page shows the sample, where the banner is the playing artist's unless a photo was
    ///   chosen, as the page itself decides it.
    public init(profile: RPMProfile?, isSample: Bool) {
        nameAtStart = profile?.displayName ?? ""
        name = nameAtStart
        followsAtStart = profile?.bannerFollowsListening == true || (isSample && profile?.bannerSource != "photo")
        follows = followsAtStart
        groundAtStart = RPMPageGround(wire: profile?.pageGround ?? "")
        ground = groundAtStart
        badgeAtStart = profile?.badge ?? ""
        badge = badgeAtStart
        colourAtStart = profile?.badgeColour ?? ""
        colour = colourAtStart
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The server takes a name of 2 to 40 characters.
    public var nameValid: Bool { (2...40).contains(trimmedName.count) }

    public var changed: Bool {
        trimmedName != nameAtStart || photo != nil || dropPhoto || banner != nil || dropBanner
            || follows != followsAtStart || ground != groundAtStart || badge != badgeAtStart || colour != colourAtStart
    }
}

/// The reader's own page, to change: every part of it is a card on this one screen, one under the other: the
/// display name, the profile photo, the banner, the background and the badge. Save at the foot sends every change at
/// once. The background behind the cards is the one chosen, so a choice can be seen. It is the Android app's
/// `EditPage`.
///
/// Closing with changes not saved asks first: apply them, or discard them.
public struct EditPage: View {
    @Bindable private var edit: ProfileEdit
    private let profile: RPMProfile?
    private let photo: URL?
    private let banner: URL?
    private let playingPhoto: URL?
    private let unlocked: [String]
    private let trouble: String?
    private let saving: Bool
    private let onSave: () -> Void
    private let onClose: () -> Void

    @State private var asking = false
    @State private var picking = false
    @State private var picked: PhotosPickerItem?
    @State private var pickingFor: PickedFor = .photo
    @State private var pictureFailed = false

    private enum PickedFor { case photo, banner }

    /// - Parameters:
    ///   - photo: the reader's photo now; ``ProfileEdit/photo`` takes its place once one is picked.
    ///   - banner: the reader's banner photo now.
    ///   - playingPhoto: the photo of the artist playing now, for the banner card; nil when nothing plays.
    ///   - unlocked: the badge ids unlocked, from the server and from this phone's own count.
    ///   - onSave: sends the changes; the caller closes the page once they are saved.
    ///   - onClose: closes the page, the changes left unsaved.
    public init(edit: ProfileEdit, profile: RPMProfile?, photo: URL?, banner: URL?, playingPhoto: URL?,
                unlocked: [String], trouble: String?, saving: Bool,
                onSave: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.edit = edit
        self.profile = profile
        self.photo = photo
        self.banner = banner
        self.playingPhoto = playingPhoto
        self.unlocked = unlocked
        self.trouble = trouble
        self.saving = saving
        self.onSave = onSave
        self.onClose = onClose
    }

    /// The solid colours a page can be drawn on, darkest last. The Android app's `PAGE_COLOURS` holds the same
    /// values, in the same order; change both.
    static let colours: [UInt32] = [
        0x2A0A5E, 0x0B1E4A, 0x0E4B4F, 0x14402A,
        0x4F1028, 0x5A2A0C, 0x2A2F38, 0x0A0A0A,
    ]

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageTitle(Loc.get("Rpm_Profile_EditPage"))
                Spacer()
                CloseKey(action: close)
            }
            .padding(.leading, RPMLayout.margin)
            .padding(.trailing, 8)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    nameCard
                    photoCard
                    bannerCard
                    backgroundCard
                    badgesCard

                    if let said = pictureFailed ? Loc.get("Rpm_Profile_PictureFailed") : trouble {
                        Text(said)
                            .font(RPMFont.display(13))
                            .foregroundStyle(RPMInk.red)
                    }

                    // Save stands under every setting, as the last thing on the page.
                    Button(action: onSave) {
                        if saving { ProgressView().tint(.white) } else { Text(Loc.get("Rpm_Profile_Save")) }
                    }
                    .buttonStyle(RPMGlassButton(.primary, radius: 14, height: 48, stretches: true, inset: 16, size: 16))
                    .disabled(!edit.changed || !edit.nameValid || saving)
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background { PageGroundView(wire: edit.ground.wire) }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            let target = pickingFor
            picked = nil
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let ready = data.flatMap { target == .photo ? PicturePrep.avatar($0) : PicturePrep.banner($0) }
                pictureFailed = ready == nil
                guard let ready else { return }
                switch target {
                case .photo:
                    edit.photo = ready
                    edit.dropPhoto = false
                case .banner:
                    edit.banner = ready
                    edit.dropBanner = false
                    edit.follows = false
                }
            }
        }
        .alert(Loc.get("Rpm_Profile_UnsavedTitle"), isPresented: $asking) {
            Button(Loc.get("Rpm_Profile_Discard"), role: .destructive, action: onClose)
            // A name the server would refuse stays on the page, to be put right first.
            Button(Loc.get("Rpm_Profile_ApplyChanges")) { if edit.nameValid { onSave() } }
        }
    }

    private func close() {
        if edit.changed { asking = true } else { onClose() }
    }

    private func pick(_ target: PickedFor) {
        pickingFor = target
        picking = true
    }

    // ── the cards ──

    /// One part of the page to change, as the settings draw theirs: a rounded card with its name at the top.
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).rpmKicker()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RPMInk.white(0x12 / 255)) }
    }

    private func smallKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(RPMGlassButton(.ghost, radius: 16, height: 34, stretches: false, inset: 18, size: 13))
    }

    private var nameCard: some View {
        card(Loc.get("Rpm_Profile_Name")) {
            TextField("", text: $edit.name)
                .font(RPMFont.display(17))
                .foregroundStyle(.white)
                .tint(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background {
                    let well = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    well.fill(RPMInk.white(0x14 / 255))
                        .overlay { well.strokeBorder(RPMInk.glassEdge, lineWidth: 1) }
                }
                .onChange(of: edit.name) { _, typed in
                    if typed.count > 40 { edit.name = String(typed.prefix(40)) }
                }
        }
    }

    private var photoCard: some View {
        let hasPhoto = edit.photo != nil || (!edit.dropPhoto && profile?.hasAvatar == true)
        return card(Loc.get("Rpm_Profile_PhotoTitle")) {
            HStack(spacing: 16) {
                ZStack {
                    if let data = edit.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                    } else {
                        PersonPicture(edit.dropPhoto ? nil : photo, name: profile?.displayName ?? "", size: 72)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    smallKey(Loc.get("Rpm_Profile_BannerPhoto")) { pick(.photo) }
                    if hasPhoto {
                        smallKey(Loc.get("Rpm_Profile_RemovePhoto")) {
                            edit.photo = nil
                            edit.dropPhoto = true
                        }
                    }
                }
            }
        }
    }

    private var bannerCard: some View {
        let own: URL? = edit.dropBanner ? nil : banner
        let hasOwn = edit.banner != nil || own != nil
        let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return card(Loc.get("Rpm_Profile_BannerTitle")) {
            // The pictures are an overlay on the well, so the well alone sets the size. A filled
            // picture reports its scaled size, and a wide photo would make the card wider than the
            // screen.
            frame.fill(RPMInk.white(0x10 / 255))
                .frame(height: 96)
                .overlay {
                    ZStack {
                        Text(Glyph.record).font(RPMFont.icon(22)).foregroundStyle(RPMInk.white(0x33 / 255))
                        if edit.follows {
                            if let playingPhoto {
                                RemotePicture(playingPhoto) { $0.resizable().scaledToFill() }
                            }
                        } else if let data = edit.banner, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if let own {
                            RemotePicture(own) { $0.resizable().scaledToFill() }
                        }
                    }
                }
                .clipShape(frame)
            .overlay { frame.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }

            choice(Loc.get("Rpm_Profile_BannerPlaying"), picked: edit.follows) { edit.follows = true }
            choice(Loc.get("Rpm_Profile_BannerOwn"), picked: !edit.follows) { edit.follows = false }

            if !edit.follows {
                HStack(spacing: 10) {
                    smallKey(Loc.get("Rpm_Profile_BannerPhoto")) { pick(.banner) }
                    if hasOwn {
                        smallKey(Loc.get("Rpm_Profile_RemoveBanner")) {
                            edit.banner = nil
                            edit.dropBanner = true
                        }
                    }
                }
            }
        }
    }

    /// A choice of one among several: a round mark, filled when it is the one chosen, and its name.
    private func choice(_ title: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(RPMInk.white(picked ? 0xF2 / 255 : 0x55 / 255), lineWidth: 2)
                    if picked { Circle().fill(.white).frame(width: 10, height: 10) }
                }
                .frame(width: 20, height: 20)
                Text(title)
                    .font(RPMFont.display(15))
                    .foregroundStyle(RPMInk.white(picked ? 1 : 0xBB / 255))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// What the page is drawn on: one of the app's backgrounds, or a solid colour. The gold background is a
    /// supporter's.
    private var backgroundCard: some View {
        card(Loc.get("Settings_Background")) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Backdrop.Choice.allCases.filter { $0 != .gold || profile?.supporter == true }, id: \.self) { choice in
                        tile(choice)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text(Loc.get("Rpm_Profile_Colours")).rpmKicker()

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Self.colours, id: \.self) { value in
                        let picked = edit.ground == .colour(value)
                        Button { edit.ground = .colour(value) } label: {
                            Circle()
                                .fill(Color(rgb: value))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Circle().strokeBorder(RPMInk.white(picked ? 0xF2 / 255 : 0x44 / 255),
                                                          lineWidth: picked ? 3 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tile(_ choice: Backdrop.Choice) -> some View {
        let ground: RPMPageGround = choice == .standard ? .standard : .backdrop(choice.rawValue)
        let picked = ground == edit.ground
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return Button { edit.ground = ground } label: {
            VStack(spacing: 6) {
                BackdropTile(choice: choice, width: 62, height: 116)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(RPMInk.white(picked ? 0xF2 / 255 : 0x33 / 255), lineWidth: picked ? 2 : 1)
                    }

                Text(Loc.get(choice.nameKey))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(picked ? 1 : 0x99 / 255))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.get(choice.nameKey))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// The badge under the name and its colour: every badge unlocked to choose from, side by side, and the ones
    /// still to unlock with what unlocks them, greyed, as achievements.
    private var badgesCard: some View {
        let held = Set(unlocked)
        let open = RPMProfileBadges.all.filter { held.contains($0.id) }
        let closed = RPMProfileBadges.all.filter { !held.contains($0.id) }

        return card(Loc.get("Rpm_Badges_Title")) {
            Text(Loc.get("Rpm_Badges_Colour")).rpmKicker()
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(RPMProfileBadges.colours, id: \.self) { value in
                        let wire = RPMProfileBadges.wire(value)
                        let picked = RPMProfileBadges.colour(edit.colour) == value
                        Button { edit.colour = wire } label: {
                            Circle()
                                .fill(Color(rgb: value))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Circle().strokeBorder(RPMInk.white(picked ? 0xF2 / 255 : 0x44 / 255),
                                                          lineWidth: picked ? 3 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text(Loc.get("Rpm_Badges_Unlocked")).rpmKicker().padding(.top, 4)

            // The badges unlocked side by side, as many on a line as fit. The one shown has a white ring.
            FlowRow(spacing: 8, lineSpacing: 10) {
                noBadge(picked: edit.badge.isEmpty)
                ForEach(open) { badge in
                    let picked = badge.id == edit.badge
                    Button { edit.badge = badge.id } label: {
                        BadgePill(badge: badge, colour: edit.colour)
                            .padding(3)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(picked ? Color.white : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }

            if !closed.isEmpty {
                Text(Loc.get("Rpm_Badges_Locked")).rpmKicker().padding(.top, 4)
                ForEach(closed) { badge in
                    VStack(alignment: .leading, spacing: 6) {
                        BadgePill(badge: badge, colour: "#555555").opacity(0.35)
                        Text(badge.need)
                            .font(RPMFont.display(12))
                            .foregroundStyle(RPMInk.white(0x88 / 255))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RPMInk.white(0x0C / 255)) }
                }
            }
        }
    }

    /// "No badge", as a chip among the badges: the choice to show none.
    private func noBadge(picked: Bool) -> some View {
        Button { edit.badge = "" } label: {
            Text(Loc.get("Rpm_Badges_NoBadge"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(RPMInk.white(picked ? 1 : 0x44 / 255), lineWidth: picked ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
