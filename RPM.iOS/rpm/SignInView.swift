import SwiftUI
import RPMSharedUI
import RPMUI
import RPMDesign
import RPMKit

/// The sign-in screen, shown whenever the user is signed out.
///
/// When signed out, the app has nothing else to show: there is no local library, only the
/// cloud. So this is the first screen, not a menu item.
///
/// It also tests the frosted glass on a real device. The record turns behind the card and the
/// card is live glass over it. The whole app depends on this combination, so if this
/// screen looks right on hardware, the design language works.
///
/// Matches `RPM.Mobile/Presentation/SignInPage.xaml`, layer by layer.
struct SignInView: View {
    let model: AppModel

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var waiting: String?

    @FocusState private var editing: Field?
    private enum Field { case email, password }

    var body: some View {
        ZStack {
            RPMInk.ground.ignoresSafeArea()

            // The record, half outside the right edge, as in the desktop's artwork band. It
            // turns from launch. Nothing is playing, but a still record would look broken.
            GeometryReader { geometry in
                RecordDisc(diameter: geometry.size.width * 0.9, halo: .round)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .offset(x: geometry.size.width * 0.9 / 2)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            // A dark gradient over the record so white text can be read, without hiding the record.
            LinearGradient(
                stops: [.init(color: RPMInk.ground.opacity(0xCC / 255), location: 0),
                        .init(color: RPMInk.ground.opacity(0x99 / 255), location: 0.55),
                        .init(color: RPMInk.ground.opacity(0xE6 / 255), location: 1)],
                startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    RPMWordmark()
                        .fill(Color.white)
                        .frame(width: 150, height: 150 / RPMWordmark.aspect)

                    Text(Loc.get("Rpm_SignIn_Subtitle"))
                        .font(.system(size: 15))
                        .foregroundStyle(RPMInk.white(0xCC / 255))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    card

                    // No register link: continuing with Apple or Google creates the account
                    // at once. No forgot-password link either. The desktop opens
                    // rpmrpmrpm.com/forgot-password, but App Review guideline 4 rejects
                    // sending the phone to Safari for this. The phone would need an in-app
                    // code flow (accounts auth/forgot-password and auth/reset-password,
                    // which email a code-only reset).
                    Text(Loc.get("Login_NewHere"))
                        .font(.system(size: 13))
                        .foregroundStyle(
                            Color(red: 0xCC / 255, green: 0xDD / 255, blue: 0xEE / 255)
                                .opacity(0xAA / 255))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                // Centred in the viewport. A scroll view puts its content at the top by
                // default, and the Uno app centres its column with
                // `VerticalAlignment="Center"`. It is still a scroll view: when the
                // keyboard is open the column is taller than the space left, so it scrolls.
                .containerRelativeFrame(.vertical, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            // Apple first: App Store guideline 4.8 requires Sign in with Apple wherever
            // another social provider is offered, and requires it to be presented as
            // an equal. The rpm user pool federates only these two providers.
            Text(Loc.get("Login_ContinueWith")).rpmKicker()

            social(Loc.get("Login_Apple"), glyph: Glyph.apple)
            social(Loc.get("Login_Google"), glyph: Glyph.google)

            divider

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
                .textContentType(.password)
                .submitLabel(.go)
                .focused($editing, equals: .password)
                .onSubmit { Task { await withPassword() } }
                .rpmField()

            if let trouble = model.trouble {
                Text(trouble)
                    .font(.system(size: 13))
                    .foregroundStyle(RPMInk.red)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(RPMInk.white(0xCC / 255))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let waiting {
                Text(waiting)
                    .font(.system(size: 13))
                    .foregroundStyle(RPMInk.white(0xCC / 255))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(Loc.get("Cloud_SignIn")) { Task { await withPassword() } }
                .buttonStyle(RPMGlassButton(.primary))

            if busy {
                ProgressView().tint(RPMInk.white(0xE6 / 255))
            }
        }
        .disabled(busy)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .rpmGlassCard()
    }

    private func social(_ name: String, glyph: String) -> some View {
        Button { Task { await withProvider(name) } } label: {
            HStack(spacing: 10) {
                if RPMFont.brandAvailable {
                    Text(glyph).font(RPMFont.brand(16))
                }
                Text(name)
            }
        }
        .buttonStyle(RPMGlassButton(.ghost))
    }

    /// A thin line with a word in a gap in the middle.
    ///
    /// It is drawn as two lines, not one line with the ground colour painted over the
    /// middle. The desktop paints over it, and there the card is glass over the same
    /// ground, so the patch cannot be seen. Over a system material the patch would show
    /// as a dark box.
    private var divider: some View {
        HStack(spacing: 10) {
            line
            Text(Loc.get("Login_Or"))
                .font(.system(size: 12))
                .foregroundStyle(RPMInk.white(0x88 / 255))
            line
        }
        .padding(.vertical, 4)
    }

    private var line: some View {
        Rectangle().fill(RPMInk.white(0x26 / 255)).frame(height: 1)
    }

    private func placeholder(_ what: String) -> Text {
        Text(what).foregroundStyle(RPMInk.white(0x77 / 255))
    }

    // ── the two ways in ──

    private func withPassword() async {
        guard !busy else { return }

        guard !email.isEmpty, !password.isEmpty else {
            model.report(Loc.get("Login_NeedFields"))
            return
        }

        busy = true
        await model.signIn(email: email, password: password)
        busy = false
    }

    private func withProvider(_ provider: String) async {
        guard !busy else { return }

        busy = true
        waiting = Loc.get("Login_WaitingBrowser")

        await model.signIn(with: provider)

        waiting = nil
        busy = false
    }
}
