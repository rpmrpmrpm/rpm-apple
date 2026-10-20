import SwiftUI
import RPMKit

/// "Start radio" on a song: it plays now, and the queue keeps filling with songs like
/// whichever one is playing (`SongRadioRun` in RPMSession). Not internet radio.
///
/// Passed down the view tree once, from the root, so every song menu (``TrackActions``) and
/// home's radio entries offer it without each page carrying one more closure. Nil where the
/// app has not set it, and then nothing offers it.
private struct StartRadioKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (CloudTrack) -> Void)? = nil
}

extension EnvironmentValues {
    public var startRadio: (@MainActor @Sendable (CloudTrack) -> Void)? {
        get { self[StartRadioKey.self] }
        set { self[StartRadioKey.self] = newValue }
    }
}
