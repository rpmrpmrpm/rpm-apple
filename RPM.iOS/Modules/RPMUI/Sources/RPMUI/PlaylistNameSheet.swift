import SwiftUI
import RPMKit

/// The card where a playlist's name is typed. It is drawn like ``WriteReviewSheet``, with the
/// app's own look.
///
/// It serves two screens: Edit playlist in a playlist page's menu (``Errand/rename(_:)``), and
/// New playlist in ``PlaylistPickSheet`` (``Errand/make(in:)``), which makes the playlist with
/// the song being filed in it.
public struct PlaylistNameSheet: View {
    /// What the card is for. The title, the key that saves and the line under the box show which.
    public enum Errand: Equatable, Sendable {
        /// Another name for a playlist that exists. The box starts with this name, the
        /// playlist's name now.
        case rename(String)

        /// A new playlist, created in this folder. An empty path is the top of the tree. The box
        /// starts empty.
        case make(in: [String])
    }

    private let errand: Errand
    private let onSave: (String) async -> String?
    private let onSaved: () -> Void
    private let onCancel: () -> Void

    /// - Parameters:
    ///   - onSave: writes the name. Answers why it failed, or nil when it is done.
    ///   - onSaved: called after `onSave` answered nil. The picker closes itself here, and not
    ///     in `onCancel`, which takes the user back to the list of playlists.
    ///   - onCancel: called when the card is put away without saving: Cancel, or a tap outside
    ///     the card.
    public init(errand: Errand, onSave: @escaping (String) async -> String?,
                onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.errand = errand
        self.onSave = onSave
        self.onSaved = onSaved
        self.onCancel = onCancel
        switch errand {
        case .rename(let name): _name = State(initialValue: name)
        case .make: _name = State(initialValue: "")
        }
    }

    @State private var name: String
    @State private var busy = false
    @State private var said: String?
    @FocusState private var typing: Bool

    private var blank: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var body: some View {
        ZStack {
            Color.black.opacity(0xB3 / 255)
                .ignoresSafeArea()
                .onTapGesture { if !busy { onCancel() } }

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(RPMFont.displayBold(19))
                    .foregroundStyle(.white)

                TextField("", text: $name,
                          prompt: Text(Loc.get("Rpm_NewPlaylist_Name"))
                              .foregroundStyle(RPMInk.white(0x66 / 255)))
                    .font(RPMFont.display(16))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background {
                        let well = RoundedRectangle(cornerRadius: 10, style: .continuous)
                        well.fill(Color.black.opacity(0x22 / 255))
                            .overlay { well.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
                    }
                    .focused($typing)

                // Where a new playlist goes. At the top of the tree there is nothing to say.
                if case .make(let folder) = errand, !folder.isEmpty {
                    Text(Loc.get("Rpm_NewPlaylist_In", folder.joined(separator: " / ")))
                        .rpmKicker()
                }

                if let said {
                    Text(said)
                        .font(RPMFont.display(12))
                        .foregroundStyle(Color(red: 1, green: 0xB4 / 255, blue: 0xA0 / 255))
                }

                HStack(spacing: 10) {
                    Button(Loc.get("Common_Cancel"), action: onCancel)
                        .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))
                        .disabled(busy)

                    Button(action: save) {
                        if busy {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text(key)
                        }
                    }
                    .buttonStyle(RPMGlassButton(.primary, radius: 10, height: 42, size: 14))
                    .disabled(busy || blank)
                }
            }
            .padding(18)
            .frame(width: 330)
            .rpmGlassCard(radius: 18)
        }
        .onAppear { typing = true }
    }

    private var title: String {
        switch errand {
        case .rename: Loc.get("Rpm_PlaylistMenu_Edit")
        case .make: Loc.get("Playlists_NewPlaylist")
        }
    }

    private var key: String {
        switch errand {
        case .rename: Loc.get("ArtPlace_Save")
        case .make: Loc.get("Rpm_NewPlaylist_Create")
        }
    }

    private func save() {
        guard !busy, !blank else { return }

        busy = true
        said = nil
        typing = false

        Task {
            let trouble = await onSave(name)
            busy = false

            guard let trouble else { onSaved(); return }
            said = trouble
        }
    }
}
