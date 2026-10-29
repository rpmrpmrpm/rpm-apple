import UIKit
import RPMKit

/// A picture of the app's screen as it is now, for a feedback report.
public enum WindowShot {
    /// The key window as PNG, the long edge at most `ShotFit.maxEdge` pixels. A picture over
    /// `ShotFit.maxBytes` is drawn smaller until it fits, at most three times; nil when it never
    /// fits or there is no window. Draws what is on screen now: call it before the feedback window
    /// opens over it.
    @MainActor
    public static func capture() -> Data? {
        guard let window = keyWindow() else { return nil }
        let bounds = window.bounds
        let pixels = window.screen.scale
        var scale = ShotFit.scale(width: bounds.width * pixels, height: bounds.height * pixels,
                                  maxEdge: ShotFit.maxEdge) * pixels

        for _ in 0..<4 {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let png = UIGraphicsImageRenderer(bounds: bounds, format: format).pngData { _ in
                _ = window.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
            if png.count <= ShotFit.maxBytes { return png }
            scale *= 0.75
        }
        return nil
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
