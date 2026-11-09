import SwiftUI
import UIKit
import QuartzCore
import RPMSharedUI

/// The opening screen, as on Android, the TV and the desktop: the rpm wordmark on black, dimmed, with
/// a band of light sweeping across it once a second until the app is ready.
///
/// The launch screen (`UILaunchScreen` in the app's Info.plist) is the same dimmed wordmark at the same
/// size and place, so nothing moves when the app's first frame replaces it; the band then lights it.
///
/// **The hand-over waits for the end of a pass.** When `ready` turns true, the band finishes the pass
/// it is in, and `onSwept` is called as it leaves the last letter. The caller fades the screen out then
/// (``fade``). `reading` is the line under the wordmark while the library is read from the cloud.
///
/// The band is a Core Animation animation, not a SwiftUI one. It runs in the render server, so a main
/// thread that is busy with the launch does not make it stutter. Android draws it on a thread of its own
/// for the same reason (`SweepSurface`).
public struct Opening: View {
    private let ready: Bool
    private let reading: String?
    private let onSwept: () -> Void

    public init(ready: Bool, reading: String?, onSwept: @escaping () -> Void) {
        self.ready = ready
        self.reading = reading
        self.onSwept = onSwept
    }

    /// How long the screen takes to fade away once the app is ready. The same as Android's
    /// `OPENING_FADE_MS`.
    public static let fade: Double = 0.6

    /// When the band started, on the media clock: a pass ends every ``SweepBand/pass`` from here.
    @State private var began = CACurrentMediaTime()

    public var body: some View {
        ZStack {
            Color.black

            // The dimmed wordmark under the band, as the launch screen draws it.
            RPMWordmark()
                .fill(Color.white.opacity(Self.dim))
                .frame(width: Self.wide, height: Self.high)

            SweepBand(began: began)
                .frame(width: Self.wide, height: Self.high)

            Text(reading ?? " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .opacity(reading == nil ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: reading)
                .offset(y: Self.high / 2 + Self.readingGap)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: ready) {
            guard ready else { return }

            let into = (CACurrentMediaTime() - began).truncatingRemainder(dividingBy: SweepBand.pass)
            try? await Task.sleep(for: .seconds(SweepBand.pass - into))
            guard !Task.isCancelled else { return }
            onSwept()
        }
    }

    /// The wordmark's size, 130 by 50 points, the same as the launch screen's picture and Android's
    /// `WORDMARK_WIDE` and `WORDMARK_HIGH`.
    static let wide: Double = 130
    static let high: Double = 50

    /// How bright the wordmark is outside the band. `DIM` in `scripts/gen_opening_wordmark.py`, which
    /// writes the launch screen's picture at the same level.
    static let dim: Double = 0.32

    /// How far under the wordmark's middle the reading line stands, past its lower half.
    static let readingGap: Double = 24
}

/// The band of light: the white wordmark, kept only under a gradient that rides across it once a second.
///
/// The band is ``bandShare`` of the wordmark wide. Its light falls from the middle to nothing at either
/// edge along a smootherstep, so it has no edge for the eye to find. Each pass is slow out of the start
/// and slow into the end. These are Android's `SweepSurface` values.
private struct SweepBand: UIViewRepresentable {
    let began: CFTimeInterval

    /// One pass across the wordmark, in seconds.
    static let pass: Double = 1

    /// The band's width, as a share of the wordmark's.
    static let bandShare: Double = 0.6

    func makeUIView(context: Context) -> Band { Band(began: began) }

    func updateUIView(_ view: Band, context: Context) {}

    final class Band: UIView {
        private let mark = CAShapeLayer()
        private let light = CAGradientLayer()
        private let began: CFTimeInterval

        init(began: CFTimeInterval) {
            self.began = began
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear

            mark.fillColor = UIColor.white.cgColor
            layer.addSublayer(mark)

            // 1 - smootherstep(distance from the middle), in 17 steps: white at the middle and nothing
            // at either edge, flat at all three.
            let steps = (0...16).map { Double($0) / 16 }
            light.colors = steps.map { step in
                let x = abs(2 * step - 1)
                let shown = 1 - x * x * x * (x * (x * 6 - 15) + 10)
                return UIColor.white.withAlphaComponent(shown).cgColor
            }
            light.locations = steps.map { NSNumber(value: $0) }
            light.startPoint = CGPoint(x: 0, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 0.5)
            mark.mask = light
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0 else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mark.frame = bounds
            mark.path = RPMWordmark().path(in: bounds).cgPath

            let band = bounds.width * SweepBand.bandShare
            light.bounds = CGRect(x: 0, y: 0, width: band, height: bounds.height)
            light.position = CGPoint(x: -band / 2, y: bounds.midY)
            CATransaction.commit()

            // The band rides from wholly before the first letter to wholly after the last. It is
            // started at `began`, so the pass the view keeps time with is the one on the screen.
            let ride = CABasicAnimation(keyPath: "position.x")
            ride.fromValue = -band / 2
            ride.toValue = bounds.width + band / 2
            ride.duration = SweepBand.pass
            ride.repeatCount = .infinity
            ride.beginTime = light.convertTime(began, from: nil)
            // Quadratic in and out, as Android's `quadInOut`.
            ride.timingFunction = CAMediaTimingFunction(controlPoints: 0.455, 0.03, 0.515, 0.955)
            ride.isRemovedOnCompletion = false
            light.add(ride, forKey: "ride")
        }
    }
}
