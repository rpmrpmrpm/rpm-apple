import SwiftUI
import RPMSharedUI
import UIKit
import RPMKit
import RPMLibrary

/// Chooses which collection the library tab shows: the user's own, or one that another
/// person has shared with them.
///
/// Ported from `RPM.Mobile/Presentation/Controls/LibraryPicker.xaml`. It has the same rows
/// in the same order: the user's own first, and the open one marked. **A shared collection
/// with no way back could make the user think their own records are gone.**
public struct LibraryPicker: View {
    private let rows: [ShelfRow]
    private let onOpen: (CloudShelf) -> Void
    private let onClose: () -> Void

    /// Offline, a shared collection cannot be read, so only the user's own is offered. Only
    /// its downloaded records can play.
    @Environment(\.rpmReach) private var reach

    public init(rows: [ShelfRow], onOpen: @escaping (CloudShelf) -> Void,
                onClose: @escaping () -> Void) {
        self.rows = rows
        self.onOpen = onOpen
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0x99 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header

                Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

                ShortScroll(rows: rows.count, each: 54, upTo: 300) {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button { onOpen(row.shelf) } label: { line(row) }
                                .buttonStyle(RowPress())
                                .disabled(!reach.isOnline && !row.isOwn)
                                .opacity(!reach.isOnline && !row.isOwn ? 0.35 : 1)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

                // Says where sharing is set up. A phone cannot be either of the two
                // computers a share is set up between, so a picker with one row needs
                // to explain itself.
                Text(Loc.get("Rpm_Share_Hint"))
                    .rpmKicker()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .frame(width: 320)
            .rpmGlassCard(radius: 18)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Loc.get("Rpm_Share_Title"))
                    .font(RPMFont.displayBold(19))
                    .foregroundStyle(.white)

                Text(rows.count == 1
                     ? Loc.get("Rpm_Share_NobodyShares")
                     : Loc.get("Rpm_Share_SharedWithYouCount", rows.count - 1))
                    .rpmKicker()
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
                Text("\u{f00d}")
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
            }
            .buttonStyle(RPMGlassKey(edge: 40))
            .accessibilityLabel(Loc.get("RecogResult_Close"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func line(_ row: ShelfRow) -> some View {
        HStack(spacing: 12) {
            PeerTile(row: row)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(row.name)
                        .font(RPMFont.display(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if row.wearsMark { SupporterMark() }
                }

                // A phone can reach only what the other person has uploaded, not files
                // that exist only on their disk.
                if !row.isOwn {
                    Text(Loc.get("Rpm_Share_CloudOnly"))
                        .font(RPMFont.display(11))
                        .foregroundStyle(RPMInk.white(0x66 / 255))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.isOpen {
                Text(Loc.get("Rpm_Share_Opened"))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
            } else {
                Text(Glyph.into)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x77 / 255))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

/// Shows whose collection a row is, in one slot.
///
/// There are three tiles, the same as the desktop share button: **their photo** when the
/// account behind the collection has one, the first letter of their name when it does not,
/// and a glyph when there is no person to draw.
///
/// The user's own row is drawn the same way, from the picture set for this account in the
/// settings. It falls back to a house glyph instead of a letter, because the name under it
/// is "My library" and not a person's name.
private struct PeerTile: View {
    let row: ShelfRow

    /// The same size as the Uno app. The fetch asks for 120 because that is three times this
    /// size, which is what the densest screen draws.
    private static let edge: CGFloat = 38

    @State private var photo: UIImage?

    /// Whether it is worth fetching at all. See ``SmallPictures/of(_:edge:reach:)``.
    @Environment(\.rpmReach) private var reach

    var body: some View {
        let well = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return ZStack {
            well.fill(RPMInk.white(0x18 / 255))

            if let photo {
                // The frame is set before the clip. An image with `.fill` is larger than
                // the well, so clipping it before it has a frame would clip nothing.
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.edge, height: Self.edge)
                    .clipShape(well)
            } else if row.initial.isEmpty {
                // A house for the user's own collection, a person for a shared
                // collection that has no photo or name.
                Text(row.isOwn ? "\u{f015}" : Glyph.profile)
                    .font(RPMFont.icon(14))
                    .foregroundStyle(RPMInk.white(0xD9 / 255))
            } else {
                Text(row.initial)
                    .font(RPMFont.display(15))
                    .foregroundStyle(RPMInk.white(0xF2 / 255))
            }
        }
        .frame(width: Self.edge, height: Self.edge)
        // Keyed on the address instead of running on appear. The list is redrawn as
        // profiles load, and a photo fetched for the previous row's owner would show the
        // wrong face under this name. The address includes the profile's stamp, so a
        // changed picture is a new key and is fetched again.
        .task(id: row.face.avatar) {
            photo = nil
            guard let address = row.face.avatar else { return }
            photo = await SmallPictures.of(address, edge: 120, reach: reach)
        }
    }
}
