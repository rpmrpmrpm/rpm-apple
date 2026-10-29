import SwiftUI
import RPMKit

/// Send feedback on the Apple TV: the same fields and rules as the phone's sheet, as rows the
/// remote moves through. Select on the kind or the area moves it to its next value; the message
/// row opens the system keyboard, which also takes text from a paired iPhone.
///
/// The screenshot is the one taken when the settings opened (`Diagnostics.heldShot`), so it shows
/// the screen the tester came from and not this one.
struct FeedbackView: View {
    @Environment(TVModel.self) private var model

    let screenshot: Data?
    let email: String?
    let onClose: () -> Void

    @State private var kind = FeedbackChoices.kinds[0].value
    @State private var area = FeedbackChoices.tvAreas[0].value
    @State private var message = ""
    @State private var includesShot = true
    @State private var replyTo = ""
    @State private var sending = false
    @State private var note: String?

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(Loc.get("Feedback_Title"))
                        .font(.tv(Size.heading, .semibold))
                        .foregroundStyle(Ink.card)
                    Text(Loc.get("Feedback_Body"))
                        .font(.tv(Size.small))
                        .foregroundStyle(Ink.dim)

                    VStack(spacing: 6) {
                        row(Loc.get("Feedback_KindLabel"), name(kind, in: FeedbackChoices.kinds)) {
                            kind = next(kind, in: FeedbackChoices.kinds)
                        }
                        row(Loc.get("Feedback_AreaLabel"), name(area, in: FeedbackChoices.tvAreas)) {
                            area = next(area, in: FeedbackChoices.tvAreas)
                        }
                        TextField(Loc.get(FeedbackChoices.placeholderKey(kind: kind)), text: $message, axis: .vertical)
                            .font(.tv(Size.row))
                        if email?.isEmpty ?? true {
                            TextField(Loc.get("Feedback_ReplyEmail"), text: $replyTo)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .font(.tv(Size.row))
                        }
                        if let screenshot, let picture = UIImage(data: screenshot) {
                            Button { includesShot.toggle() } label: {
                                HStack(spacing: 24) {
                                    Text(Loc.get("Feedback_Screenshot"))
                                        .font(.tv(Size.row, .semibold))
                                        .foregroundStyle(Ink.words)
                                    Spacer(minLength: 40)
                                    Image(uiImage: picture)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 160)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .opacity(includesShot ? 1 : 0.3)
                                    Text(Loc.get(includesShot ? "Viz_SettingOn" : "Viz_SettingOff"))
                                        .font(.tv(Size.row))
                                        .foregroundStyle(Color.white.opacity(0xCC / 255))
                                }
                            }
                            .buttonStyle(RowStyle())
                        }
                    }

                    Text(Loc.get("Feedback_Sends"))
                        .font(.tv(Size.small))
                        .foregroundStyle(Ink.dim)
                    if let email, !email.isEmpty {
                        Text(Loc.get("Feedback_RepliesTo", email))
                            .font(.tv(Size.small))
                            .foregroundStyle(Ink.dim)
                    }
                    if let note {
                        Text(note)
                            .font(.tv(Size.row))
                            .foregroundStyle(Ink.card)
                    }

                    HStack(spacing: 24) {
                        Button(Loc.get("Feedback_Send")) { Task { await press() } }
                            .disabled(sending)
                        Button(Loc.get("Common_Cancel"), action: onClose)
                    }
                }
                .frame(width: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.top, Size.top)
                .padding(.bottom, 80)
            }
        }
    }

    private func row(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
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
    }

    private func name(_ value: String, in choices: [FeedbackChoices.Choice]) -> String {
        Loc.get(choices.first(where: { $0.value == value })?.key ?? choices[0].key)
    }

    private func next(_ value: String, in choices: [FeedbackChoices.Choice]) -> String {
        let at = choices.firstIndex(where: { $0.value == value }) ?? 0
        return choices[(at + 1) % choices.count].value
    }

    private func press() async {
        let typed = replyTo.trimmingCharacters(in: .whitespaces)
        let draft = FeedbackDraft(
            kind: kind, area: area, message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            screenshotPng: includesShot ? screenshot : nil, replyTo: typed.isEmpty ? nil : typed)
        guard draft.isSendable else {
            note = Loc.get("Feedback_NeedWords")
            return
        }

        sending = true
        defer { sending = false }
        switch await model.diagnostics.sendFeedback(draft) {
        case .sent:
            // The thanks stays on screen long enough to read, then the screen closes itself.
            note = Loc.get("Feedback_Sent")
            try? await Task.sleep(for: .seconds(1.5))
            onClose()
        case .failed: note = Loc.get("Feedback_Failed")
        case .busy: break
        }
    }
}
