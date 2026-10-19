import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import RPMKit
import RPMSharedUI

/// Sign-in on a TV: one QR code per provider. The person scans one with a phone and signs in
/// there. The TV gets the session by polling.
struct SignInView: View {
    @Environment(TVModel.self) private var model

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
                    .frame(height: 420)
            case .unreachable:
                Text(Loc.get("Rpm_Net_Failed"))
                    .font(.tv(Size.note))
                    .foregroundStyle(Ink.words)
                    .frame(height: 420)
            case .codes(let codes):
                HStack(spacing: 96) {
                    ForEach(codes) { QRTile(code: $0) }
                }
                .frame(height: 420)
            }

            Text(Loc.get("Tv_SignIn_Scan"))
                .font(.tv(Size.row))
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
        }
        .padding(60)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One provider's QR code, black on white with its quiet zone, and the provider's name below it.
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
