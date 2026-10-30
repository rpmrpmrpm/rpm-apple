import SwiftUI
import RPMSharedUI
import RPMUI
import RPMDesign
import RPMKit

/// Making an rpm account with an email and password, as a card on the sign-in screen.
///
/// The same three steps as the desktop's sign-up window: the form goes to the accounts service
/// (`auth/register`), which mails a six-digit code; the code is typed here (`auth/confirm`); and the
/// new account is signed in with the password just chosen. The screen then changes to the app.
///
/// Everything happens in the app. App Review guideline 4 rejects sending the phone to Safari to make
/// an account, and the mail carries only a code, so no browser is needed.
struct SignUpCard: View {
    /// Where the card opens.
    enum Start: Equatable {
        case form

        /// An account that was made and never confirmed. The sign-in screen opens the code step for it,
        /// because the mail carries only a code. No new code is sent on opening: it would replace the
        /// one already in the person's inbox.
        case code(email: String, password: String)
    }

    let model: AppModel
    let start: Start

    /// Back to the sign-in card.
    let back: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var onCode = false
    @State private var busy = false
    @State private var trouble: String?
    @State private var notice: String?

    @FocusState private var editing: Field?
    private enum Field { case name, email, password, code }

    var body: some View {
        VStack(spacing: 14) {
            Text(Loc.get("SignUp_Title")).rpmKicker()

            if onCode { codeFace } else { formFace }

            if let trouble {
                said(trouble, colour: RPMInk.red)
            } else if let notice {
                said(notice, colour: RPMInk.white(0xCC / 255))
            }

            Button(Loc.get(onCode ? "SignUp_Confirm" : "SignUp_Create")) { Task { await go() } }
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
            if case .code(let email, let password) = start {
                self.email = email
                self.password = password
                onCode = true
                editing = .code
            } else {
                editing = .name
            }
        }
    }

    private var formFace: some View {
        VStack(spacing: 14) {
            TextField("", text: $name, prompt: placeholder(Loc.get("SignUp_Name")))
                .textContentType(.name)
                .submitLabel(.next)
                .focused($editing, equals: .name)
                .onSubmit { editing = .email }
                .rpmField()

            TextField("", text: $email, prompt: placeholder(Loc.get("Login_Email")))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($editing, equals: .email)
                .onSubmit { editing = .password }
                .rpmField()

            SecureField("", text: $password, prompt: placeholder(Loc.get("Login_Password")))
                .textContentType(.newPassword)
                .submitLabel(.go)
                .focused($editing, equals: .password)
                .onSubmit { Task { await go() } }
                .rpmField()

            Text(Loc.get("SignUp_PasswordRule"))
                .font(.system(size: 12))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var codeFace: some View {
        VStack(spacing: 14) {
            Text(Loc.get("SignUp_CodeSent", email))
                .font(.system(size: 13))
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .multilineTextAlignment(.center)

            TextField("", text: $code, prompt: placeholder(Loc.get("SignUp_Code")))
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .medium).monospacedDigit())
                .focused($editing, equals: .code)
                .rpmField()

            Button(Loc.get("SignUp_Resend")) { Task { await resend() } }
                .font(.system(size: 13))
                .foregroundStyle(RPMInk.white(0xCC / 255))
        }
    }

    private func said(_ line: String, colour: Color) -> some View {
        Text(line)
            .font(.system(size: 13))
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
        if onCode { await confirm() } else { await register() }
        busy = false
    }

    private func register() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            trouble = Loc.get("SignUp_NeedFields")
            return
        }

        if let refused = await model.auth.signUp(name: name, email: email, password: password).said {
            trouble = refused
            return
        }
        onCode = true
        editing = .code
    }

    private func confirm() async {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else {
            trouble = Loc.get("SignUp_NeedCode")
            return
        }

        if let refused = await model.auth.confirmSignUp(email: email, code: code).said {
            trouble = refused
            return
        }

        // The account is live: sign it in with the password it was made with. On success the app
        // replaces this screen. A second Confirm after a failed sign-in is safe, because the service
        // answers a confirmed account as done.
        if await model.signIn(email: email, password: password) != .signedIn {
            trouble = model.trouble ?? Loc.get("SignUp_Failed")
        }
    }

    private func resend() async {
        guard !busy else { return }
        trouble = nil
        notice = nil
        busy = true
        let answer = await model.auth.resendSignUpCode(email: email)
        busy = false
        if let refused = answer.said { trouble = refused } else { notice = Loc.get("SignUp_CodeResent") }
    }
}
