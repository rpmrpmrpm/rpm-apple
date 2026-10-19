import SwiftUI
import RPMKit

/// The sheet for deleting the account. It says what will be deleted and asks the person to type
/// the account's email to confirm.
///
/// It is built like ``NewPlaylistSheet``: a glass panel over a scrim, with **Cancel and the
/// Delete key in the header**. The text field opens the keyboard, and the keyboard would cover
/// the bottom of the panel. The Delete key is red and stays dim until the field holds the
/// address. The comparison ignores case and surrounding spaces, as the accounts service does.
///
/// The request runs while the panel is still shown, so an error appears where the person is
/// looking and they can try again. On success the app signs out and this panel closes with the
/// profile page.
public struct DeleteAccountSheet: View {
    private let email: String

    /// Does the deleting. Returns nil when it is done and an error sentence when it fails, the
    /// same convention as ``NewPlaylistSheet``.
    private let commit: () async -> String?

    private let onClose: () -> Void

    public init(email: String, commit: @escaping () async -> String?, onClose: @escaping () -> Void) {
        self.email = email
        self.commit = commit
        self.onClose = onClose
    }

    @State private var typed = ""
    @State private var busy = false
    @State private var trouble: String?
    @FocusState private var typing: Bool

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(email.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    public var body: some View {
        ZStack {
            // Tapping outside the panel cancels, except while the request is running, because the
            // person is waiting for its result.
            Color.black.opacity(0xB3 / 255)
                .ignoresSafeArea()
                .onTapGesture { if !busy { onClose() } }

            panel
                .padding([.horizontal, .bottom], 8)
        }
        .onAppear { typing = true }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                Text(Loc.get("Account_DeleteBody"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xD9 / 255))
                    .fixedSize(horizontal: false, vertical: true)

                Text(Loc.get("Account_DeleteTypeEmail", email))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xD9 / 255))
                    .fixedSize(horizontal: false, vertical: true)

                TextField("", text: $typed,
                          prompt: Text(email).foregroundStyle(RPMInk.white(0x77 / 255)))
                    .rpmField()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($typing)
                    .submitLabel(.done)
                    .disabled(busy)
                    .onSubmit { Task { await delete() } }

                if let trouble {
                    Text(trouble)
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .rpmGlassCard(radius: 18)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(Loc.get("Common_Cancel")) { onClose() }
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 38,
                                            stretches: false, inset: 14, size: 14))
                .disabled(busy)

            Text(Loc.get("Account_DeleteTitle"))
                .font(RPMFont.displayBold(17))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            Button { Task { await delete() } } label: {
                if busy {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Text(Loc.get("Account_Delete")).foregroundStyle(RPMInk.red)
                }
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 38,
                                        stretches: false, inset: 14, size: 14))
            .disabled(!matches || busy)
            .opacity(matches && !busy ? 1 : 0.45)
            .accessibilityLabel(Loc.get("Account_Delete"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func delete() async {
        guard matches, !busy else { return }
        busy = true
        trouble = nil
        typing = false

        let failed = await commit()

        busy = false
        if let failed {
            trouble = failed
            typing = true
        }
    }
}
