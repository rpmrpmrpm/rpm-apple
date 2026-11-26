import SwiftUI
import RPMSharedUI
import RPMUI
import RPMDesign
import RPMKit

/// Choosing a new password for an rpm account, as a card on the sign-in screen.
///
/// Two steps, both in the app: the email goes to the accounts service (`auth/forgot-password`),
/// which mails a six-digit code; then the code and the new password go back
/// (`auth/reset-password`). The account is then signed in with the new password, and the screen
/// changes to the app.
///
/// Everything happens in the app. App Review guideline 4 rejects sending the phone to Safari for
/// this, and the mail carries only a code, so no browser is needed. The TV, which cannot type well,
/// shows a QR code of ``RpmSite/forgotPassword`` instead.
struct ResetCard: View {
    let model: AppModel

    /// What was typed in the sign-in card's email field. The card opens with it filled in.
    let email: String

    /// Back to the sign-in card.
    let back: () -> Void

    /// Back to the sign-in card after the password was changed and the sign-in with it did not
    /// finish. It hands back the address, for the sign-in card's email field.
    let changed: (String) -> Void

    @State private var address = ""
    @State private var code = ""
    @State private var password = ""
    @State private var onCode = false
    @State private var busy = false
    @State private var trouble: String?
    @State private var notice: String?

    @FocusState private var editing: Field?
    private enum Field { case email, code, password }

    var body: some View {
        VStack(spacing: 14) {
            Text(Loc.get("Reset_Title")).rpmKicker()

            if onCode { codeFace } else { emailFace }

            if let trouble {
                said(trouble, colour: RPMInk.red)
            } else if let notice {
                said(notice, colour: RPMInk.white(0xCC / 255))
            }

            Button(Loc.get(onCode ? "Reset_Save" : "Reset_Send")) { Task { await go() } }
                .buttonStyle(RPMGlassButton(.primary))

            Button(Loc.get("Common_Cancel"), action: back)
                .buttonStyle(RPMGlassButton(.ghost))

            if busy {
                ProgressView().tint(RPMInk.white(0xE6 / 255))
            }
        }
        .disabled(busy)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .rpmGlassCard()
        .onAppear {
            address = email
            editing = .email
        }
    }

    private var emailFace: some View {
        VStack(spacing: 14) {
            Text(Loc.get("Reset_Subtitle"))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .multilineTextAlignment(.center)

            TextField("", text: $address, prompt: placeholder(Loc.get("Login_Email")))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($editing, equals: .email)
                .onSubmit { Task { await go() } }
                .rpmField()
        }
    }

    private var codeFace: some View {
        VStack(spacing: 14) {
            Text(Loc.get("Reset_CodeSent", address))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .multilineTextAlignment(.center)

            TextField("", text: $code, prompt: placeholder(Loc.get("SignUp_Code")))
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(RPMFont.text(18, weight: .medium).monospacedDigit())
                .focused($editing, equals: .code)
                .rpmField()

            SecureField("", text: $password, prompt: placeholder(Loc.get("Reset_NewPassword")))
                .textContentType(.newPassword)
                .submitLabel(.go)
                .focused($editing, equals: .password)
                .onSubmit { Task { await go() } }
                .rpmField()

            Text(Loc.get("SignUp_PasswordRule"))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(Loc.get("SignUp_Resend")) { Task { await resend() } }
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xCC / 255))
        }
    }

    private func said(_ line: String, colour: Color) -> some View {
        Text(line)
            .font(RPMFont.display(13))
            .foregroundStyle(colour)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ what: String) -> Text {
        Text(what).foregroundStyle(RPMInk.white(0x77 / 255))
    }

    // ── the steps ──

    private func go() async {
        guard !busy else { return }
        trouble = nil
        notice = nil
        busy = true
        if onCode { await save() } else { await send() }
        busy = false
    }

    private func send() async {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
            trouble = Loc.get("Reset_NeedEmail")
            return
        }

        if let refused = await model.auth.forgotPassword(email: address).saidOnSend {
            trouble = refused
            return
        }
        onCode = true
        editing = .code
    }

    private func save() async {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            trouble = Loc.get("Reset_NeedFields")
            return
        }

        if let refused = await model.auth.resetPassword(email: address, code: code, password: password).saidOnSave {
            trouble = refused
            return
        }

        // The password is changed: sign in with it. On success the app replaces this screen. If the
        // sign-in does not finish, the sign-in card opens with the address in it and says that the
        // new password works, so the person can try again there.
        if await model.signIn(email: address, password: password) != .signedIn {
            changed(address.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func resend() async {
        guard !busy else { return }
        trouble = nil
        notice = nil
        busy = true
        let answer = await model.auth.forgotPassword(email: address)
        busy = false
        if let refused = answer.saidOnSend { trouble = refused } else { notice = Loc.get("SignUp_CodeResent") }
    }
}
