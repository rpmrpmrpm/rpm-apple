import SwiftUI
import RPMKit
import RPMLibrary
import RPMSession
import RPMSharing
import RPMSharedUI

/// The collections and the computers. The collections are shown as a profile picker, as in the
/// Android TV app: "Choose library" over the account's own collection and each collection that
/// another account shares with it. Each has a large picture with its name and how it is shared under
/// it, a tick by the open one, and the supporter mark for supporters. Then come the computers on the
/// network that share rpm and the computers that this TV has paired with.
/// Select on a computer that is here and not paired starts pairing: the computer shows a six-digit
/// code, which the user types here. The music of a paired computer joins the account's own
/// collection while the computer is on the network.
struct CollectionsView: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens

    var body: some View {
        let session = model.session
        let home = model.homeNetwork

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 26) {
                Text(Loc.get("Tv_ChooseLibrary"))
                    .font(.tv(64, .bold))
                    .foregroundStyle(Ink.words)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 60) {
                    // The account's own collection under its screen name and photo, as the phone's
                    // picker draws it. It shows "My collection" until the profile is read.
                    let own = session.shelfRows.first(where: \.isOwn)?.face ?? .nobody
                    LibraryTile(mark: .symbol("house.fill"), photo: own.avatar,
                                name: own.isKnown ? own.displayName : Loc.get("Share_MyLibrary"),
                                line: Loc.get("Share_MyLibrary"),
                                open: session.viewing.isOwn, supporter: false) { switchTo(.own) }
                    ForEach(session.shelfRows.filter { !$0.isOwn }) { row in
                        LibraryTile(mark: row.initial.isEmpty ? .symbol("person.fill") : .letter(row.initial),
                                    photo: row.face.avatar, name: row.name,
                                    line: Loc.get("Rpm_Share_CloudOnly"),
                                    open: row.isOpen, supporter: row.wearsMark) { switchTo(row.shelf) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .focusSpace("collections")
                .focusSection()

                // How many collections are shared, and where sharing is set up, as the phone's
                // picker shows.
                let shared = session.shelfRows.filter { !$0.isOwn }.count
                VStack(alignment: .leading, spacing: 6) {
                    Text(shared == 0 ? Loc.get("Rpm_Share_NobodyShares") : Loc.get("Rpm_Share_SharedWithYouCount", String(shared)))
                        .font(.tv(Size.small, .semibold))
                        .foregroundStyle(Ink.artist)
                    Text(Loc.get("Rpm_Share_Hint"))
                        .font(.tv(Size.small))
                        .foregroundStyle(Ink.dim)
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.leading, RowStyle.inset)

                // The heading and the message line up with the content of the rows, not with their
                // highlighted background.
                Text(Loc.get("Tv_Menu_Computers"))
                    .font(.tv(Size.heading, .semibold))
                    .foregroundStyle(Ink.card)
                    .padding(.top, 30)
                    .padding(.leading, RowStyle.inset)

                if home.rows.isEmpty {
                    Text(Loc.get("Tv_Computers_None"))
                        .font(.tv(Size.note))
                        .foregroundStyle(Ink.dim)
                        .padding(.leading, RowStyle.inset)
                } else {
                    VStack(spacing: 6) {
                        ForEach(home.rows) { computer in
                            CollectionRow(mark: .symbol("laptopcomputer"), name: computer.name,
                                          line: computer.paired
                                            ? (computer.here != nil ? Loc.get("Tv_Computer_Connected") : Loc.get("Tv_Computer_Away"))
                                            : Loc.get("Tv_Computer_Connect"),
                                          open: computer.paired && computer.here != nil) {
                                if !computer.paired, let found = computer.here {
                                    home.pair(found, account: session.who?.userId)
                                }
                            }
                        }
                    }
                    .focusSpace("computers")
                    .focusSection()
                }
            }
            .frame(width: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, Size.top)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .task { await session.readShares() }
        .sheet(isPresented: pairing) {
            PairingPanel()
        }
    }

    private var pairing: Binding<Bool> {
        Binding(get: { model.homeNetwork.pairing != nil },
                set: { if !$0 { model.homeNetwork.cancelPairing() } })
    }

    /// Another collection opens on its home, as the desktop app's switch does.
    private func switchTo(_ shelf: CloudShelf) {
        guard shelf.ownerId != model.session.viewing.ownerId else { return }
        Task { await model.session.open(shelf) }
        screens.paths = [:]
        screens.tab = .home
    }
}

/// A round mark: a symbol or a letter.
enum CollectionMark { case symbol(String), letter(String) }

/// The face of a collection or a computer: the photo of its owner, or its round mark until the
/// photo has loaded (or if there is no photo), in a circle `edge` wide.
private struct CollectionFace: View {
    let mark: CollectionMark
    /// The owner's photo. It has no default: a face created without it would draw a letter for a
    /// person who has a picture.
    let photo: URL?
    let edge: CGFloat

    @Environment(\.rpmReach) private var reach
    @State private var picture: UIImage?
    @State private var pictureOf: URL?

    /// The size of the photo in the well, which is the size it is stored at: the largest size drawn.
    private static let photoEdge: CGFloat = 216

    var body: some View {
        let picture = pictureOf == photo ? self.picture : photo.flatMap { SmallPictures.inMemory($0, edge: Self.photoEdge) }
        ZStack {
            Circle().fill(Color.white.opacity(0x1A / 255))
            switch mark {
            case .symbol(let symbol):
                Image(systemName: symbol).font(.system(size: edge * 0.39)).foregroundStyle(Ink.card)
            case .letter(let letter):
                Text(letter).font(.tv(edge * 0.42, .semibold)).foregroundStyle(Ink.card)
            }
            if let picture {
                Image(uiImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(Circle())
        // The task depends on the address: a face redrawn for another person must not keep the
        // photo of the last person.
        .task(id: photo) {
            guard let photo else { return }
            let had = SmallPictures.inMemory(photo, edge: Self.photoEdge) != nil
            let found = await SmallPictures.of(photo, edge: Self.photoEdge, reach: reach)
            guard !Task.isCancelled else { return }
            var put = Transaction()
            if !had { put.animation = .easeOut(duration: 0.25) }
            withTransaction(put) {
                self.picture = found
                pictureOf = photo
            }
        }
    }
}

/// One library in the picker: the large picture of its owner, its name, and how it is shared, with a
/// tick before it on the open one, and the supporter mark under it for a supporter.
private struct LibraryTile: View {
    let mark: CollectionMark
    let photo: URL?
    let name: String
    let line: String
    let open: Bool
    let supporter: Bool
    let action: () -> Void

    static let edge: CGFloat = 220

    var body: some View {
        Button(action: action) {
            CollectionFace(mark: mark, photo: photo, edge: Self.edge)
                .hoverEffect(.highlight)
            VStack(spacing: 6) {
                Text(name)
                    .font(.tv(Size.row, .semibold))
                    .foregroundStyle(Ink.words)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if open {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Ink.words)
                    }
                    Text(line)
                        .font(.tv(Size.rowLine))
                        .foregroundStyle(Ink.artist)
                        .lineLimit(1)
                }
                if supporter { SupporterMark() }
            }
            .frame(width: Self.edge + 60)
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.circle)
        .remembered("library:" + name)
    }
}

/// A computer: its round mark, its name, a line under it, and a tick on the connected one.
private struct CollectionRow: View {
    typealias Mark = CollectionMark

    let mark: Mark
    let name: String
    let line: String?
    let open: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                CollectionFace(mark: mark, photo: nil, edge: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.tv(Size.row, .semibold))
                        .foregroundStyle(Ink.words)
                        .lineLimit(1)
                    if let line {
                        Text(line)
                            .font(.tv(Size.rowLine))
                            .foregroundStyle(Ink.artist)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if open {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Ink.words)
                }
            }
        }
        .buttonStyle(RowStyle())
        .remembered("row:" + name)
    }
}

/// The pairing card: what the computer is doing, the code field while the computer shows a code, and
/// OK when the pairing has ended. Back cancels a pairing that is in progress.
private struct PairingPanel: View {
    @Environment(TVModel.self) private var model
    @State private var code = ""

    var body: some View {
        let home = model.homeNetwork
        VStack(spacing: 36) {
            if let pairing = home.pairing {
                Text(message(pairing))
                    .font(.tv(40, .semibold))
                    .foregroundStyle(Ink.words)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1000)

                switch pairing {
                case .asking:
                    RecordSpinner(diameter: 64)
                case .showingCode(_, let triesLeft, let wrong):
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .font(.tv(48, .semibold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(width: 420)
                        .onChange(of: code) { _, typed in
                            let digits = String(typed.filter(\.isNumber).prefix(6))
                            if digits != typed { code = digits }
                            // Six digits are the whole code. They are sent at once and the field
                            // is cleared.
                            if digits.count == 6 {
                                home.submit(digits)
                                code = ""
                            }
                        }
                    if wrong {
                        Text(Loc.get("Share_CodeWrongTries", String(triesLeft)))
                            .font(.tv(Size.rowLine))
                            .foregroundStyle(Ink.failed)
                    }
                case .ended:
                    Button(Loc.get("Common_OK")) { home.cancelPairing() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(60)
    }

    private func message(_ pairing: Pairing) -> String {
        switch pairing {
        case .asking(let name): Loc.get("Tv_Pair_Asking", name)
        case .showingCode(let name, _, _): Loc.get("Share_EnterCode", name)
        case .ended(let name, let how):
            switch how {
            case .accepted: Loc.get("Tv_Pair_Accepted", name)
            case .declined: Loc.get("Tv_Pair_Declined", name)
            case .expired: Loc.get("Tv_Pair_Expired")
            case .tooManyTries: Loc.get("Share_TooManyTries")
            case .full: Loc.get("Share_Full", name)
            case .lost: Loc.get("Share_Lost", name)
            case .failed: Loc.get("Tv_Pair_Failed", name)
            }
        }
    }
}
