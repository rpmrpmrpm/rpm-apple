import SwiftUI
import RPMKit
import RPMSharedUI

/// The Apple TV app. It has the same cloud, sign-in and library as the phone app, laid out for a
/// remote.
///
/// The model is created here, once, and passed down. Every screen reads it from the environment.
@main
struct RPMApp: App {
    @State private var model = TVModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TVRoot()
                .environment(model)
                // Every station logo (StationFace) reads it; a logo drawn without it stops the app.
                .environment(model.stations.radioState)
                .task {
                    // The crash handlers first, then the report scope, which sends or asks about
                    // the crashes that are waiting.
                    CrashWatch.install(arrived: { [model] in Task { await model.diagnostics.crashArrived() } })
                    Task { await model.diagnostics.start() }
                    await model.start()
                }
                .onChange(of: phase) { _, now in
                    switch now {
                    case .active: CrashWatch.sceneBecameActive()
                    case .background:
                        model.diagnostics.sceneLeftActive()
                        CrashWatch.sceneWentToBackground()
                    default: model.diagnostics.sceneLeftActive()
                    }
                }
                .alert(Loc.get("Crash_PromptTitle"),
                       isPresented: Binding(get: { model.diagnostics.asksAboutCrashes }, set: { _ in })) {
                    Button(Loc.get("Crash_PromptSend")) { Task { await model.diagnostics.answer(send: true) } }
                    Button(Loc.get("Crash_PromptDontSend"), role: .cancel) {
                        Task { await model.diagnostics.answer(send: false) }
                    }
                } message: {
                    Text(Loc.get("Crash_PromptBody"))
                }
        }
    }
}
