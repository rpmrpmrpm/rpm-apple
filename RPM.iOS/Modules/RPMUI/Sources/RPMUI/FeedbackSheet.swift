import SwiftUI
import RPMKit

/// The Send feedback window: something that went wrong, or something that could be better, with a
/// screenshot of the screen it was opened over and the app's recent log.
///
/// The same fields and rules as the desktop window. The message is the report, so an empty box is
/// refused here. A failed send says so and keeps what was written, so it can be sent again. Raised
/// as a sheet, like ``AboutPage``, and without a `NavigationStack` for the same reason.
public struct FeedbackSheet: View {
    public typealias Send = (FeedbackDraft) async -> Diagnostics.Sent

    private let screenshot: Data?
    private let email: String?
    private let send: Send
    private let onClose: () -> Void

    @State private var kind = FeedbackChoices.kinds[0].value
    @State private var area = FeedbackChoices.phoneAreas[0].value
    @State private var message = ""
    @State private var includesShot = true
    @State private var replyTo = ""
    @State private var sending = false
    @State private var note: String?

    /// - Parameters:
    ///   - screenshot: the screen as it was before the sheet opened, or nil when it could not be read.
    ///   - email: the signed-in account's address, where replies go, or nil when signed out.
    public init(screenshot: Data?, email: String?, send: @escaping Send, onClose: @escaping () -> Void) {
        self.screenshot = screenshot
        self.email = email
        self.send = send
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            RPMInk.ground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    words(Loc.get("Feedback_Body"), 13, 0xB3)

                    choices

                    TextField(Loc.get(FeedbackChoices.placeholderKey(kind: kind)), text: $message, axis: .vertical)
                        .lineLimit(5...12)
                        .font(RPMFont.display(15))
                        .foregroundStyle(.white)
                        .padding(12)
                        .rpmSection()

                    if let screenshot, let picture = UIImage(data: screenshot) {
                        Toggle(isOn: $includesShot) { words(Loc.get("Feedback_Screenshot"), 13, 0xB3) }
                            .tint(RPMInk.white(0x88 / 255))
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .opacity(includesShot ? 1 : 0.3)
                    }

                    words(Loc.get("Feedback_Sends"), 11, 0x88)

                    if let email, !email.isEmpty {
                        words(Loc.get("Feedback_RepliesTo", email), 11, 0x88)
                    } else {
                        TextField(Loc.get("Feedback_ReplyEmail"), text: $replyTo)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(RPMFont.display(14))
                            .foregroundStyle(.white)
                            .padding(12)
                            .rpmSection()
                    }

                    if let note { words(note, 13, 0xE0) }

                    Button(Loc.get("Feedback_Send")) { Task { await press() } }
                        .buttonStyle(RPMGlassButton(.primary))
                        .disabled(sending)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top) { bar }
    }

    private var bar: some View {
        HStack {
            Button(Loc.get("Common_Cancel"), action: onClose)
                .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 34, stretches: false, inset: 16, size: 13))
            Spacer()
            Text(Loc.get("Feedback_Title")).rpmKicker()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.get("Feedback_KindLabel")).rpmKicker()
            Picker(Loc.get("Feedback_KindLabel"), selection: $kind) {
                ForEach(FeedbackChoices.kinds) { Text(Loc.get($0.key)).tag($0.value) }
            }
            .pickerStyle(.segmented)

            Text(Loc.get("Feedback_AreaLabel")).rpmKicker()
            Picker(Loc.get("Feedback_AreaLabel"), selection: $area) {
                ForEach(FeedbackChoices.phoneAreas) { Text(Loc.get($0.key)).tag($0.value) }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
    }

    private func words(_ text: String, _ size: CGFloat, _ white: Int) -> some View {
        Text(text)
            .font(RPMFont.display(size))
            .foregroundStyle(RPMInk.white(Double(white) / 255))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func press() async {
        let draft = FeedbackDraft(
            kind: kind, area: area, message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            screenshotPng: includesShot ? screenshot : nil,
            replyTo: replyTo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : replyTo)
        guard draft.isSendable else {
            note = Loc.get("Feedback_NeedWords")
            return
        }

        sending = true
        defer { sending = false }
        switch await send(draft) {
        case .sent:
            // The thanks stays on screen long enough to read, then the sheet closes itself.
            note = Loc.get("Feedback_Sent")
            try? await Task.sleep(for: .seconds(1.5))
            onClose()
        case .failed: note = Loc.get("Feedback_Failed")
        case .busy: break
        }
    }
}
