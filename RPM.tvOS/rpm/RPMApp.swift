import SwiftUI

/// The Apple TV app. It has the same cloud, sign-in and library as the phone app, laid out for a
/// remote.
///
/// The model is created here, once, and passed down. Every screen reads it from the environment.
@main
struct RPMApp: App {
    @State private var model = TVModel()

    var body: some Scene {
        WindowGroup {
            TVRoot()
                .environment(model)
                // Every station logo (StationFace) reads it; a logo drawn without it stops the app.
                .environment(model.stations.radioState)
                .task { await model.start() }
        }
    }
}
