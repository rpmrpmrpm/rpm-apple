import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import RPMKit
import RPMSharedUI

/// Sign-in on a TV: one QR code per provider. The person scans one with a phone and signs in
/// there, after checking that the phone shows the code under the QR code. The TV gets the session by
/// polling.
///
/// Under the codes is a quieter key for a forgotten password. It opens a sheet with a QR code of
/// ``RpmSite/forgotPassword``, and Back closes it. The polling runs in ``TVModel``, not in this view,
/// so it goes on while the sheet is up.
struct SignInView: View {
    @Environment(TVModel.self) private var model

    @State private var forgetting = false

    var body: some View {
        VStack(spacing: 40) {
            RPMWordmark()
                .fill(Color.white)
                .frame(width: 240, height: 240 / RPMWordmark.aspect)
            Text(Loc.get("Rpm_SignIn_Subtitle"))
                .font(.tv(31))
                .foregroundStyle(Color.white.opacity(0.82))

            switch model.signIn {
            case .starting:
                RecordSpinner(diameter: 96)
                    .frame(height: 500)
            case .unreachable:
                Text(Loc.get("Rpm_Net_Failed"))
                    .font(.tv(Size.note))
                    .foregroundStyle(Ink.words)
                    .frame(height: 500)
            case .codes(let codes):
                HStack(spacing: 96) {
                    ForEach(codes) { QRTile(code: $0) }
                }
                .frame(height: 500)
            }

            // The key sits close under the line, so the card still fits the screen's safe area.
            VStack(spacing: 24) {
                Text(Loc.get("Tv_SignIn_Scan"))
                    .font(.tv(Size.row))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Button(Loc.get("Login_Forgot")) { forgetting = true }
                    .font(.tv(Size.small))
                    .buttonStyle(.glass)
            }
        }
        .padding(60)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $forgetting) {
            ForgotPanel()
        }
    }
}

/// The QR code of the password reset page, with how to use it. The page mails a link where the
/// person chooses a new password, so the TV only shows the way there. The sheet closes with Back.
private struct ForgotPanel: View {
    var body: some View {
        VStack(spacing: 36) {
            Text(Loc.get("Login_Forgot"))
                .font(.tv(40, .semibold))
                .foregroundStyle(Ink.words)
                .multilineTextAlignment(.center)

            if let picture = QR.image(of: RpmSite.forgotPassword.absoluteString) {
                Image(decorative: picture, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 320, height: 320)
                    .padding(20)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            Text(Loc.get("Tv_SignIn_ForgotScan"))
                .font(.tv(Size.row))
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
                // Focusable, so the remote rests inside the sheet. Nothing in it takes a key but Back.
                .focusable()
        }
        .padding(60)
    }
}

/// One provider's QR code, black on white with its quiet zone, the provider's name below it, and the
/// code to compare with the phone's sign-in page.
private struct QRTile: View {
    let code: SignInCode

    var body: some View {
        VStack(spacing: 20) {
            if let picture = QR.image(of: code.url.absoluteString) {
                Image(decorative: picture, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 320, height: 320)
                    .padding(20)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            Text(code.provider == "Google" ? Loc.get("Login_Google") : Loc.get("Login_Apple"))
                .font(.tv(Size.row, .semibold))
                .foregroundStyle(Ink.words)
            if let userCode = code.userCode {
                Text(Loc.get("Tv_SignIn_Code", userCode))
                    .font(.tv(Size.note))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .frame(width: 360)
            }
        }
    }
}

/// Makes a QR code from a string. It has one image pixel per module and no margin. The white box
/// around the code provides the quiet zone.
enum QR {
    static func image(of text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
