import SwiftUI
import UIKit
import RPMKit
import RPMSharedUI

/// The player, shown over everything (`PlayerPresenter`). It draws the room as the root view draws
/// it behind the player. Over the room is the line along the bottom edge. The root's own line is
/// covered while the player is up. It fades with the screens when the screensaver hides them.
struct PlayerCover: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    @Environment(Screensaver.self) private var saver

    var body: some View {
        ZStack {
            RoomLayer(collection: false, screensaver: saver.shown)

            PlayerScreen()
                .opacity(saver.shown ? 0 : 1)
                .animation(.easeInOut(duration: saver.shown ? 1.5 : 0.4), value: saver.shown)

            FlashLine(text: model.flashText, count: model.flashCount)
                .opacity(saver.shown ? 0 : 1)
        }
        .ignoresSafeArea()
        // tvOS shows the cover in a window of its own. The screens' press watcher does not see
        // presses in that window, so the cover has its own watcher.
        .background(PressWatcher.app(saver: saver, screens: screens))
        .modifier(WriteQuestions(active: screens.playerShown))
    }
}

/// Presents the player over everything, through UIKit. tvOS's own players are presented this way.
/// tvOS moves the focus into the player. When the player closes, tvOS gives the focus back to the
/// view that had it, if it can still find it (for example, search results). A screen that keeps its
/// own focus takes back its remembered card.
///
/// This is not SwiftUI's `fullScreenCover`. That one closes on the first Back before anything
/// inside is asked. The player's first Back should only hide its keys, as on Android TV. Drawing
/// the player over the screens, with the screens disabled under it, is also wrong. The focus would
/// then come back to nothing, and Back would leave the app. Over an open search, the player would
/// never get the focus, because tvOS holds the focus inside an active search controller.
struct PlayerPresenter: UIViewControllerRepresentable {
    let model: TVModel
    let screens: Screens
    let saver: Screensaver
    let reach: Reach

    func makeUIViewController(context: Context) -> Anchor { Anchor() }

    func updateUIViewController(_ anchor: Anchor, context: Context) {
        let model = model, screens = screens, saver = saver, reach = reach
        anchor.content = {
            AnyView(PlayerCover()
                // The player is presented over the screens, not inside them, so it takes the
                // Picture setting itself.
                .overlay { PictureOver() }
                .environment(model)
                .environment(screens)
                .environment(saver)
                .environment(model.stations.radioState)
                .environment(\.rpmReach, reach))
        }
        anchor.back = { screens.backInPlayer() }
        anchor.close = { screens.playerShown = false }
        anchor.closed = {
            if screens.paths[screens.tab, default: []].isEmpty { screens.giveFocusBack() }
        }
        anchor.want(shown: screens.playerShown)
    }

    /// An invisible controller in the screens' tree, from whose window the player is presented.
    final class Anchor: UIViewController {
        var content: () -> AnyView = { AnyView(EmptyView()) }
        var back: () -> Bool = { false }
        var close: () -> Void = {}
        var closed: () -> Void = {}
        private var wanted = false
        private weak var player: PlayerController?

        func want(shown: Bool) {
            wanted = shown
            settle()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            settle()
        }

        private func settle() {
            if wanted, player == nil {
                // Presented over whatever is on top of the window: the screens, or a search
                // controller that holds the focus.
                guard var top = view.window?.rootViewController else { return }
                while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
                let made = PlayerController(rootView: content())
                made.back = { [weak self] in self?.back() ?? false }
                made.close = { [weak self] in self?.close() }
                // Over the screens, not instead of them. A full-screen presentation removes the
                // screens from the window. They would then come back without the card each one
                // remembered. The player's own room is opaque, so nothing under it shows.
                made.modalPresentationStyle = .overFullScreen
                made.modalTransitionStyle = .crossDissolve
                player = made
                top.present(made, animated: true)
            } else if !wanted, let player {
                self.player = nil
                // Pass the callback itself, not this anchor. SwiftUI may have made a new anchor by
                // the time the player has gone.
                let closed = closed
                player.close { closed() }
            }
        }
    }
}

/// The player's controller. Back is handled by the player first. What is inside is asked first (the
/// queue drawer, then the player's keys). Otherwise the player closes. tvOS's own Back on a
/// presentation calls `dismiss` on this controller (the back gesture of
/// `UIPresentationController`). That would close the player on the first Back, while the keys are
/// still up. So that call is checked here first. The player's own close (from `Anchor`) goes
/// through `close(_:)`.
final class PlayerController: UIHostingController<AnyView> {
    var back: () -> Bool = { false }
    var close: () -> Void = {}

    /// Set while the player is closed on purpose. Then `dismiss` does what it says.
    private var closing = false

    func close(completion: @escaping () -> Void) {
        closing = true
        dismiss(animated: true, completion: completion)
    }

    override func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        // A menu or alert over the player closes as normal.
        guard !closing, presentedViewController == nil else {
            super.dismiss(animated: animated, completion: completion)
            return
        }
        if !back() { close() }
    }
}

/// The questions that a write to a playlist asks: whether to add a song again to a list that
/// already holds it, and the name of a new list. They are shown from the view on top, which is
/// `active`. That is either the screens, or the player while it is up. A presentation cannot be
/// shown from a view that is already showing another one.
struct WriteQuestions: ViewModifier {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let active: Bool

    @State private var newName = ""

    private var naming: Binding<Bool> {
        Binding(get: { active && screens.naming != nil }, set: { if !$0 { screens.naming = nil } })
    }

    func body(content: Content) -> some View {
        content
            .alert(Loc.get("Rpm_PlaylistPick_AlreadyIn", screens.fileAgain?.list.name ?? ""),
                   isPresented: Binding(get: { active && screens.fileAgain != nil }, set: { if !$0 { screens.fileAgain = nil } }),
                   presenting: screens.fileAgain) { asked in
                Button(Loc.get("Cloud_Cancel"), role: .cancel) { screens.fileAgain = nil }
                Button(Loc.get("Rpm_PlaylistPick_AddAgain")) {
                    screens.fileAgain = nil
                    model.file(asked.track, in: asked.list, whenAlreadyThere: .addAnother)
                }
            } message: { _ in
                Text(Loc.get("Rpm_PlaylistPick_AlreadyInBody"))
            }
            .alert(Loc.get("Playlists_NewPlaylist"), isPresented: naming) {
                TextField(Loc.get("Rpm_NewPlaylist_Name"), text: $newName)
                Button(Loc.get("Rpm_NewPlaylist_Create")) {
                    if let track = screens.naming { model.file(track, inNew: newName) }
                    newName = ""
                }
                Button(Loc.get("Common_Cancel"), role: .cancel) { newName = "" }
            }
    }
}

/// The Picture setting over the player, read as it changes.
private struct PictureOver: View {
    @Environment(TVModel.self) private var model

    var body: some View { PictureLayers(look: model.settings.picture) }
}

