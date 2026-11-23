import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary
import RPMStages

/// The welcome on the very first launch, after signing in: the desktop's setup wizard (`WizardPage`),
/// made for the phone.
///
/// The phone has nothing to set up that the desktop's wizard sets up (a folder, an import, an
/// account to make). So it keeps the desktop's greeting and its look and layout steps, and ends with
/// a song from the person's own collection, played in the player while its hints show the player
/// round. The Android app shows the same welcome, without the language step and the look step's
/// sliders and colours.
///
/// - **Hello**: "Welcome to rpm!" on black, the drifting room coming up behind it, the greeting
///   turning through the app's languages every five seconds, as the desktop's does.
/// - **Language**: the app's language. The one tapped is used at once.
/// - **Look**: the backdrops, how much they are dimmed and blurred, and the colour of the app's
///   glass. Each change shows behind the step at once.
/// - **Layout**: how the records open in the collection: the grid of covers, or the list with the
///   songs.
/// - **Spin**: a song from the collection (``WelcomeSong``), and the key that plays it and opens
///   the player.
///
/// The steps carry the desktop's "Step 1 of 3" and its row of dots. Every touch stops at the
/// welcome: the app under it is not in play yet.
///
/// **The step shown is kept for the scene, not by the view** (``page``). A new language builds the
/// app's screens again, the welcome with them, and the welcome must open again on the language
/// step and not on the greeting.
public struct Welcome: View {
    private let covers: any CoverStore
    private let pick: () -> (album: CloudAlbum, at: Int)?
    private let onPlay: (CloudAlbum, Int) -> Void
    private let onDone: () -> Void

    /// - Parameters:
    ///   - pick: chooses the song the last step plays. Asked once, when the welcome appears. Nil
    ///     leaves that step out, and the layout step ends the welcome.
    ///   - onPlay: plays the song (its record, from its place) and opens the player. The welcome is
    ///     over then.
    ///   - onDone: ends the welcome without playing.
    public init(covers: any CoverStore,
                pick: @escaping () -> (album: CloudAlbum, at: Int)?,
                onPlay: @escaping (CloudAlbum, Int) -> Void,
                onDone: @escaping () -> Void) {
        self.covers = covers
        self.pick = pick
        self.onPlay = onPlay
        self.onDone = onDone
    }

    /// The step shown: 0 is the greeting, then the language, the look, the layout and the song.
    @SceneStorage("welcome.page") private var page = 0

    /// The song the last step plays, with its record and its place on it.
    @State private var sample: Sample?

    private struct Sample {
        let album: CloudAlbum
        let at: Int
        var track: CloudTrack { album.tracks[at] }
    }

    /// How many numbered steps there are: the greeting is not one.
    private var steps: Int { sample != nil ? 4 : 3 }

    public var body: some View {
        ZStack {
            // The ground: the drifting room for the greeting, the chosen backdrop for the steps after
            // it.
            ZStack {
                if page == 0 {
                    HelloRoom()
                        .transition(.opacity)
                } else {
                    VinylGround()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.7), value: page == 0)
            .ignoresSafeArea()

            ZStack {
                switch page {
                case 0:
                    WelcomeHello(onContinue: { go(to: 1) })
                case 1:
                    WelcomeStep(at: 1, of: steps, title: Loc.get("Wizard_Phone_LanguageTitle"),
                                line: Loc.get("Wizard_Phone_LanguageHint"), next: { go(to: 2) }) {
                        WelcomeLanguages()
                    }
                case 2:
                    WelcomeStep(at: 2, of: steps, title: Loc.get("Wizard_LookTitle"),
                                line: Loc.get("Wizard_Phone_LookAllHint"), next: { go(to: 3) }) {
                        VStack(alignment: .leading, spacing: 18) {
                            WelcomeBackdrops()
                            BackdropVeilSliders()

                            VStack(alignment: .leading, spacing: 10) {
                                Text(Loc.get("Settings_Colour")).rpmKicker()
                                AppColourBubbles()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text(Loc.get("Settings_CoverCorners")).rpmKicker()
                                CoverCornerSlider()
                            }
                        }
                    }
                case 3:
                    WelcomeStep(at: 3, of: steps, title: Loc.get("Wizard_LayoutTitle"),
                                line: Loc.get("Wizard_Phone_LayoutBody"),
                                next: { if sample != nil { go(to: 4) } else { finish(onDone) } },
                                nextLabel: sample == nil ? Loc.get("Wizard_Finish") : nil) {
                        WelcomeLayouts()
                    }
                default:
                    if let sample {
                        WelcomeStep(at: 4, of: steps, title: Loc.get("Wizard_Phone_PlayerTitle"),
                                    line: Loc.get("Wizard_Phone_PlayerBody"),
                                    next: { finish { onPlay(sample.album, sample.at) } },
                                    nextLabel: Loc.get("Wizard_Phone_PlayerGo"),
                                    skip: { finish(onDone) }) {
                            WelcomeSample(album: sample.album, track: sample.track, covers: covers)
                        }
                    }
                }
            }
            .id(page)
            .transition(AnyTransition.asymmetric(
                insertion: AnyTransition.opacity.animation(.easeOut(duration: 0.28).delay(0.17)),
                removal: AnyTransition.opacity.animation(.easeIn(duration: 0.17))))
        }
        .background(Color.black.ignoresSafeArea())
        // Every touch stops here: the app under the welcome is not in play yet.
        .contentShape(Rectangle())
        .onAppear {
            if sample == nil, let chosen = pick() { sample = Sample(album: chosen.album, at: chosen.at) }
        }
    }

    private func go(to next: Int) {
        Haptics.pick()
        withAnimation { page = next }
    }

    /// Ends the welcome. The step kept for the scene goes back to the greeting, so a welcome shown
    /// again from the settings starts at the beginning.
    private func finish(_ then: () -> Void) {
        page = 0
        then()
    }
}

/// The desktop's step colour: the lit dots, the picked choice's edge.
private let accent = RPMInk.cyan

/// The drifting room behind the greeting, faded in a second after the words, as the desktop's comes
/// in.
private struct HelloRoom: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black

            if RoomView.works {
                RoomView(colours: .still, sound: .still, foot: 1, running: true, breathes: true,
                         zero: .whenShown, seed: "welcome")
                    .opacity(shown ? 1 : 0)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.5)) { shown = true }
        }
    }
}

/// "Welcome to rpm!", turning through the app's languages, the line under it and the key that goes
/// on.
private struct WelcomeHello: View {
    let onContinue: () -> Void

    /// The app's languages the greeting turns through: the desktop's `AppLanguage.Offered`.
    private static let greeted = ["en", "fr", "es", "de", "zh-Hans"]

    /// How long each greeting stays.
    private static let turn: Duration = .seconds(5)

    /// The greeting in each language, the phone's own first, then the others in the desktop's order.
    private static let greetings: [String] = {
        let own = Locale.current.language.languageCode?.identifier ?? "en"
        let first = WelcomeHello.greeted.first {
            Locale(identifier: $0).language.languageCode?.identifier == own
        } ?? "en"
        var seen = Set<String>()
        return ([first] + WelcomeHello.greeted.filter { $0 != first })
            .map { Loc.get("Wizard_Hello", in: $0) }
            .filter { seen.insert($0).inserted }
    }()

    @State private var shownAt = 0
    @State private var words = false
    @State private var rest = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Text(Self.greetings[shownAt])
                    .font(RPMFont.displayBold(44))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .id(shownAt)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.7), value: shownAt)
            .opacity(words ? 1 : 0)

            VStack(spacing: 28) {
                Text(Loc.get("Wizard_HelloSubtitle"))
                    .font(RPMFont.display(18))
                    .foregroundStyle(RPMInk.white(0xC4 / 255))
                    .multilineTextAlignment(.center)

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text(Loc.get("Wizard_Continue"))
                        Text(Glyph.into).font(RPMFont.icon(11))
                    }
                }
                .buttonStyle(RPMGlassButton(.ghost, stretches: false, inset: 28))
            }
            .opacity(rest ? 1 : 0)
            .allowsHitTesting(rest)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.7)) { words = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.7)) { rest = true }
        }
        .task {
            let count = Self.greetings.count
            guard count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.turn)
                guard !Task.isCancelled else { return }
                shownAt = (shownAt + 1) % count
            }
        }
    }
}

/// One step: "Step 2 of 3", the title and the line under it, the step's own choices, and at the foot
/// the row of dots with the key that goes on. `skip` adds "Skip for now" beside it.
private struct WelcomeStep<Content: View>: View {
    let at: Int
    let of: Int
    let title: String

    /// The line under the title.
    let line: String
    let next: () -> Void
    let nextLabel: String?
    let skip: (() -> Void)?
    let content: () -> Content

    init(at: Int, of: Int, title: String, line: String, next: @escaping () -> Void,
         nextLabel: String? = nil, skip: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.at = at
        self.of = of
        self.title = title
        self.line = line
        self.next = next
        self.nextLabel = nextLabel
        self.skip = skip
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Loc.get("Wizard_StepOf", at, of).uppercased())
                        .rpmKicker()

                    Text(title)
                        .font(RPMFont.displayBold(28))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(line)
                        .font(RPMFont.display(14))
                        .lineSpacing(3)
                        .foregroundStyle(RPMInk.white(0xC4 / 255))
                        .fixedSize(horizontal: false, vertical: true)

                    content()
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                // The desktop's dots: lit up to the step showing.
                HStack(spacing: 9) {
                    ForEach(1...max(1, of), id: \.self) { dot in
                        Circle()
                            .fill(dot <= at ? accent : RPMInk.white(0x38 / 255))
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

                if let skip {
                    Button(action: skip) {
                        Text(Loc.get("Wizard_SkipForNow"))
                            .font(.system(size: 14))
                            .foregroundStyle(RPMInk.white(0xB3 / 255))
                            .padding(10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button(nextLabel ?? Loc.get("Wizard_Next"), action: next)
                    .buttonStyle(RPMGlassButton(.primary, stretches: false, inset: 22))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}

/// A choice as the desktop's wizard draws one (`WizardChoices`): a faint tile with a cyan edge while
/// it is picked.
private struct WelcomeChoice<Content: View>: View {
    let picked: Bool
    let onPick: () -> Void
    let content: () -> Content

    init(picked: Bool, onPick: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.picked = picked
        self.onPick = onPick
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        Button {
            Haptics.pick()
            onPick()
        } label: {
            content()
                .padding(6)
                .background { shape.fill(RPMInk.white(0x13 / 255)) }
                .overlay {
                    shape.strokeBorder(picked ? accent : RPMInk.white(0x2B / 255), lineWidth: 2)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The backdrops, as the settings page shows them, larger. The one tapped is the ground at once.
/// The supporters' backdrop shows only for a supporter.
private struct WelcomeBackdrops: View {
    /// The same key every page's ground reads (``VinylGround``).
    @AppStorage(Backdrop.key) private var backdropId = ""

    /// The glass colour. Choosing a background sets it back to the background's own colour.
    @AppStorage(AppColour.key) private var glassColour = ""

    private static let tileWide: Double = 104
    private static let tileTall: Double = 186

    var body: some View {
        let gold = SupporterGround.isGold
        let standing = Backdrop.standing(stored: backdropId, gold: gold)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Backdrop.Choice.allCases.filter { !$0.isSupporters || gold }, id: \.self) { choice in
                    WelcomeChoice(picked: choice == standing, onPick: { backdropId = choice.rawValue; glassColour = "" }) {
                        VStack(spacing: 8) {
                            BackdropTile(choice: choice, width: Self.tileWide, height: Self.tileTall)
                                .frame(width: Self.tileWide, height: Self.tileTall)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(Loc.get(choice.nameKey))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: Self.tileWide)
                        }
                    }
                    .accessibilityLabel(Loc.get(choice.nameKey))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

/// The app's languages, each named in itself, with the phone's own first. The one tapped is used at
/// once: the app shows itself again in it, the welcome too, on this step.
private struct WelcomeLanguages: View {
    @AppStorage(Loc.chosenKey) private var chosen = ""

    var body: some View {
        VStack(spacing: 10) {
            row("", Loc.get("Settings_AppLanguagePhone"))
            ForEach(Loc.offered, id: \.self) { code in
                row(code, Loc.name(of: code))
            }
        }
    }

    private func row(_ code: String, _ said: String) -> some View {
        let picked = (Loc.offered.contains(chosen) ? chosen : "") == code

        return WelcomeChoice(picked: picked, onPick: { if !picked { Loc.choose(code) } }) {
            Text(said)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }
}

/// The two ways the records open: the grid of covers and the list with the songs.
private struct WelcomeLayouts: View {
    /// The same key the collection's own switch writes (``LibraryPage``).
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid

    var body: some View {
        VStack(spacing: 12) {
            ForEach(LibraryLayout.allCases, id: \.self) { choice in
                WelcomeChoice(picked: layout == choice, onPick: { layout = choice }) {
                    HStack(spacing: 16) {
                        Text(choice.mark)
                            .font(RPMFont.icon(30))
                            .foregroundStyle(accent)
                            .frame(width: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.label)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(Loc.get(choice == .grid ? "Wizard_LayoutWallDesc" : "Wizard_LayoutListDesc"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(RPMInk.white(0x8C / 255))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                }
            }
        }
    }
}

/// The song the last step plays: its cover, its title and its artist.
private struct WelcomeSample: View {
    let album: CloudAlbum
    let track: CloudTrack
    let covers: any CoverStore

    @State private var cover: Cover?

    private static let edge: Double = 200

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0x22 / 255))

                if let cover {
                    Sleeve(image: cover.image)
                        .transition(.opacity)
                } else {
                    Text(Glyph.record)
                        .font(RPMFont.icon(44))
                        .foregroundStyle(RPMInk.white(0x3A / 255))
                }
            }
            .frame(width: Self.edge, height: Self.edge)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
            }

            Text(track.title ?? "")
                .font(RPMFont.displayBold(20))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(track.artist ?? album.artist)
                .font(RPMFont.display(15))
                .foregroundStyle(RPMInk.white(0xB3 / 255))
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .task(id: album.key) {
            if cover == nil { cover = covers.coverHeld(for: album, edge: Self.edge) }
            let found = await covers.cover(for: album, edge: Self.edge)
            withAnimation(.easeOut(duration: 0.25)) { cover = found ?? cover }
        }
    }
}
