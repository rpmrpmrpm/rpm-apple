import SwiftUI
import RPMKit

/// The card over a playlist page where the playlist's name is changed: Edit playlist in the
/// page's menu. It is drawn over the page like ``WriteReviewSheet``, with the app's own look.
public struct PlaylistNameSheet: View {
    private let onSave: (String) async -> String?
    private let onClose: () -> Void

    /// - Parameters:
    ///   - name: the name the box starts with: the playlist's name now.
    ///   - onSave: writes the new name. Answers why it failed, or nil when it is done.
    public init(name: String, onSave: @escaping (String) async -> String?,
                onClose: @escaping () -> Void) {
        self.onSave = onSave
        self.onClose = onClose
        _name = State(initialValue: name)
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
                .onTapGesture { if !busy { onClose() } }

            VStack(alignment: .leading, spacing: 14) {
                Text(Loc.get("Rpm_PlaylistMenu_Edit"))
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

                if let said {
                    Text(said)
                        .font(RPMFont.display(12))
                        .foregroundStyle(Color(red: 1, green: 0xB4 / 255, blue: 0xA0 / 255))
                }

                HStack(spacing: 10) {
                    Button(Loc.get("Common_Cancel"), action: onClose)
                        .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))
                        .disabled(busy)

                    Button(action: save) {
                        if busy {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text(Loc.get("ArtPlace_Save"))
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

    private func save() {
        guard !busy, !blank else { return }

        busy = true
        said = nil
        typing = false

        Task {
            let trouble = await onSave(name)
            busy = false

            guard let trouble else { onClose(); return }
            said = trouble
        }
    }
}
