import SwiftUI
import RPMSharedUI
import RPMSession
import RPMRadio
import RPMKit

/// Internet radio: the desktop app's pane, sized for a phone.
///
/// This is the phone version of `RPM.Mobile/Presentation/RadioPage.xaml`. It shows the dial,
/// then the stations that the dial can reach. **The two are views of one thing**: whatever is
/// listed is what the needle can land on, so dragging the needle and tapping a row tune the
/// same station.
///
/// A station plays through the player, like everything else here: tapping a row tunes
/// it in, and the mark in the gutter shows which one is on, as for a track in the
/// library. Pausing is done by the strip, which also shows for a station.
public struct RadioPage: View {
    private let stations: [RadioStation]

    /// The listener's own saved stations, or the saved stations of a shared library's owner, which
    /// the hearts do not change. See ``SavedStations``.
    private let saved: SavedStations
    private let tuned: String?
    private let announced: String
    private let standing: Standing

    private let onSearch: (String, String?, String?) async -> Void
    private let onTune: (RadioStation) -> Void
    private let onSave: (RadioStation) -> Void
    private let countries: [RadioFacet]

    /// What the page is doing, when it is not simply showing stations: the state of the read that
    /// this page waits for. The TV app shares it; see `RPMSession`.
    public typealias Standing = DirectoryStanding

    public init(stations: [RadioStation], saved: SavedStations, countries: [RadioFacet],
                tuned: String?, announced: String, standing: Standing,
                onSearch: @escaping (String, String?, String?) async -> Void,
                onTune: @escaping (RadioStation) -> Void,
                onSave: @escaping (RadioStation) -> Void) {
        self.stations = stations
        self.saved = saved
        self.countries = countries
        self.tuned = tuned
        self.announced = announced
        self.standing = standing
        self.onSearch = onSearch
        self.onTune = onTune
        self.onSave = onSave
    }

    @State private var asked = ""
    @State private var genre: String?
    @State private var country: String?

    /// The order of the list. **It applies to what is listed, like the sieve beside
    /// it**: an A to Z order of the dial sorts the stations in hand, not the
    /// forty thousand that the directory holds. See ``StationSort``.
    @State private var order: StationOrdering = .listed

    /// **A filter, not a place.** It is the one view that works with no network at
    /// all, so it is one tap away and not a screen of its own.
    @State private var showingSaved = false

    /// What the search has settled on. A keystroke is not a question to the directory, and
    /// volunteers run the directory.
    @State private var settled = ""

    public var body: some View {
        VStack(spacing: 0) {
            header

            // The dial works out everything it draws from its own width, so it fits
            // any phone without extra settings.
            RadioDial(stations: onTheDial, tuned: tuned, announced: announced, onTune: onTune)
                .padding(.horizontal, RPMLayout.margin)
                .padding(.top, 4)

            // The stations scroll under the filter row only, so the scroll edge ends at the
            // foot of the dial. If the list also scrolled under the dial, it would look as if
            // it slid behind a picture.
            list
                .frame(maxHeight: .infinity)
                .scrollsUnder {
                    VStack(spacing: 0) {
                        controls

                        if standing == .directoryDown {
                            trouble
                        }
                    }
                }
        }
        .background { VinylGround() }
        .task(id: settled) { await onSearch(settled, genre, country) }
        .task(id: asked) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            settled = asked
        }
        .onChange(of: country) { Task { await onSearch(settled, genre, country) } }

        // The genre also asks the directory, and not only because the answer is bigger.
        // The page in hand holds the most listened-to stations and may hold no metal
        // stations at all, so Metal would be empty however the tags were read.
        // The saved stations are a local list and do not ask the directory.
        .onChange(of: genre) {
            guard !showingSaved else { return }
            Task { await onSearch(settled, genre, country) }
        }
    }

    // ── what the dial and the list are showing ──

    /// The saved stations, or what the directory answered with, narrowed by the
    /// genre and put in the order asked for. **The sieve narrows what is listed**,
    /// so the same question also works over the saved stations with no
    /// network. Picking a genre also asks the directory for that genre's tag,
    /// so the sieve reads a page of the right kind of station and not
    /// whatever was listed. What it removes there is what the tag brought in by mistake,
    /// such as the reggaeton stations behind "reggae".
    ///
    /// The names are made distinct last, after the narrowing and the ordering. Whether two
    /// stations need their straplines to be told apart depends on the list that is shown on
    /// screen, and the sieve can remove one of them.
    private var onTheDial: [RadioStation] {
        let held = showingSaved ? saved.stations : stations
        return RadioNames.distinguish(
            StationSort.by(order, StationSieve(genre: genre).through(held)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PageTitle.subtitleGap) {
            PageTitle(Loc.get("Rpm_Tab_Radio"))

            Text(Loc.get("Radio_Subtitle")).rpmKicker()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RPMLayout.margin)
        // No top padding: the SafeArea.Insets of the Uno head replace the ten points that its
        // markup asks for, so its headers start at the safe area. See `LibraryPage.header`.
        .padding(.bottom, 8)
    }

    // ── the search and the two filters ──

    /// On the desktop these share one row. A phone is not wide enough, so the box
    /// takes one line and the filters take the line under it.
    private var controls: some View {
        VStack(spacing: 8) {
            TextField("", text: $asked,
                      prompt: Text(Loc.get("Radio_SearchPlaceholder")).foregroundStyle(RPMInk.white(0x77 / 255)))
                .rpmField()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            HStack(spacing: 8) {
                // Plain strings, unlike the country box beside it: the kinds of
                // station are a fixed list and not an answer from the directory.
                chooser(genre ?? Loc.get("Radio_AllGenres")) {
                    Button(Loc.get("Radio_AllGenres")) { genre = nil }
                    Divider()
                    ForEach(StationSieve.genres, id: \.self) { kind in
                        Button(kind) { genre = kind }
                    }
                }

                chooser(countries.first { $0.code == country }?.name ?? Loc.get("Radio_AllCountries")) {
                    Button(Loc.get("Radio_AllCountries")) { country = nil }
                    Divider()
                    // Names only, as on the desktop. The count decides which countries are
                    // listed, and the list is shown A to Z.
                    ForEach(countries) { where_ in
                        Button(where_.name) { country = where_.code }
                    }
                }

                // Icon-only, unlike the two boxes beside it. A third box with "Most
                // played" in it would make the genre and the country boxes too narrow to
                // read, and of the three filters the order is almost always the
                // directory's own.
                Menu {
                    Picker(Loc.get("Radio_SortHeading"), selection: $order) {
                        ForEach(StationOrdering.allCases, id: \.self) { which in
                            Text(named(which)).tag(which)
                        }
                    }
                } label: {
                    key(Glyph.sortAmount, on: order != .listed)
                }
                .accessibilityLabel(Loc.get("Radio_Sort"))

                Button { showingSaved.toggle() } label: {
                    key(Glyph.heart, on: showingSaved)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.get("Radio_ShowFavorites"))
            }
        }
        .padding(.horizontal, RPMLayout.margin)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// One of the two square keys at the end of the filter row. **Cyan when it is in
    /// force**, which is the whole of its state. Without it, a list in a chosen order, or
    /// narrowed to the saved stations, would give no sign of that, and the page would
    /// seem to be missing stations.
    private func key(_ glyph: String, on: Bool) -> some View {
        Text(glyph)
            .font(RPMFont.icon(14))
            .foregroundStyle(on ? RPMInk.cyan : RPMInk.white(0x88 / 255))
            .frame(width: 44, height: 40)
            .background {
                let well = RoundedRectangle(cornerRadius: 8, style: .continuous)
                well.fill(on ? RPMInk.cyan.opacity(0x1F / 255) : RPMInk.white(0x14 / 255))
                    .overlay {
                        well.strokeBorder(on ? RPMInk.cyan.opacity(0x55 / 255)
                                             : RPMInk.white(0x1A / 255),
                                          lineWidth: 1)
                    }
            }
    }

    /// The name that the menu shows for one order.
    private func named(_ order: StationOrdering) -> String {
        switch order {
        case .listed: return Loc.get("Radio_SortListed")
        case .nameUp: return Loc.get("Radio_SortNameUp")
        case .nameDown: return Loc.get("Radio_SortNameDown")
        case .votes: return Loc.get("Radio_SortVotes")
        case .quality: return Loc.get("Radio_SortQuality")
        }
    }

    private func chooser<Content: View>(
        _ said: String, @ViewBuilder _ options: () -> Content
    ) -> some View {
        Menu(content: options) {
            HStack(spacing: 6) {
                Text(said)
                    .font(RPMFont.display(13))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Glyph.sort).font(RPMFont.icon(10))
            }
            .foregroundStyle(RPMInk.white(0xE6 / 255))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                let well = RoundedRectangle(cornerRadius: 8, style: .continuous)
                well.fill(RPMInk.white(0x14 / 255))
                    .overlay { well.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
            }
        }
    }

    /// Why the list is short, when it is. **It has its own row above the list and does not
    /// float over it**: a message over the rows would cover the first station, and both would be
    /// unreadable. The message is most needed when there are rows under it.
    private var trouble: some View {
        Text(Loc.get("Radio_DirectoryDown"))
            .font(RPMFont.display(12))
            .foregroundStyle(RPMInk.white(0xAA / 255))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                let well = RoundedRectangle(cornerRadius: 8, style: .continuous)
                well.fill(Color.black.opacity(0x22 / 255))
                    .overlay { well.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
            }
            .padding(.horizontal, RPMLayout.margin)
            .padding(.bottom, 10)
    }

    // ── the stations ──

    @ViewBuilder
    private var list: some View {
        let showing = onTheDial

        if showing.isEmpty {
            empty
        } else {
            // The stations dissolve at the top of the list. The page's own header
            // and its search are above this and do not move, so this is the only edge
            // on the screen where rows scroll away.
            DissolvingScroll {
                LazyVStack(spacing: 0) {
                    ForEach(showing) { station in
                        Button { onTune(station) } label: { row(station) }
                            .buttonStyle(RowPress())
                    }
                    Color.clear.frame(height: RPMLayout.foot)
                }
            }
            .scrollIndicators(.hidden)
            .keyboardRoom()
            .scrollDismissesKeyboard(.interactively)
            // At the head of the list and not in the middle, because the list underneath
            // still shows the stations of the last search while a new search runs. It is
            // small for the same reason: the screen is not empty, and the spinner only
            // shows that more is coming.
            .overlay(alignment: .top) {
                if standing == .reading {
                    RecordSpinner(diameter: 34).padding(.top, 18)
                }
            }
        }
    }

    private func row(_ station: RadioStation) -> some View {
        HStack(spacing: 10) {
            // The playing mark is in the list's own left inset and not in front of
            // the row. The marks stay on one line and the mark has the gutter to
            // itself. It is the same three points of white that the album's track list uses.
            Rectangle()
                .fill(station.uuid == tuned ? Color.white : .clear)
                .frame(width: 3, height: 26)
                .clipShape(Capsule())

            // The station's own mark, as the Uno head draws it. An antenna is shown
            // if a station has no mark or its link no longer works.
            StationLogo(station: station)

            VStack(alignment: .leading, spacing: 1) {
                // The AD mark is right after the name, as on the desktop. The name gives
                // way to it: a long name is cut short, and the mark is not.
                HStack(spacing: 6) {
                    Text(station.display)
                        .font(RPMFont.display(14))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if RadioAds.carriesAds(tags: station.tags, name: station.name,
                                           homepage: station.homepage) {
                        AdsBadge().layoutPriority(1)
                    }
                }

                Text(said(station))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The one key on the row: saving the station. The bundled Font Awesome has the
            // Solid style only, so "saved" is shown by colour and not by a hollow
            // heart. In a shared library the saved stations belong to its owner: their
            // heart is shown and cannot be pressed, and the other stations have no heart.
            if saved.mayChange {
                Button { Haptics.commit(); onSave(station) } label: {
                    Text(Glyph.heart)
                        .font(RPMFont.icon(14))
                        .foregroundStyle(isSaved(station) ? RPMInk.cyan : RPMInk.white(0x44 / 255))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.get("Radio_Save"))
            } else if isSaved(station) {
                Text(Glyph.heart)
                    .font(RPMFont.icon(14))
                    .foregroundStyle(RPMInk.cyan)
                    .frame(width: 40, height: 44)
                    .accessibilityLabel(Loc.get("Radio_SavedMark"))
            } else {
                Color.clear.frame(width: 40, height: 44)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func isSaved(_ station: RadioStation) -> Bool {
        saved.stations.contains { $0.uuid == station.uuid }
    }

    private func said(_ station: RadioStation) -> String {
        var parts: [String] = []
        let country = RadioCountries.short(station.country, station.countryCode)
        if !country.isEmpty { parts.append(country) }
        if !station.genres.isEmpty { parts.append(station.genres.prefix(3).joined(separator: ", ")) }
        if !station.quality.isEmpty { parts.append(station.quality) }

        return parts.joined(separator: "  \u{b7}  ")
    }

    @ViewBuilder
    private var empty: some View {
        VStack(spacing: 10) {
            if standing == .reading || (showingSaved && saved == .reading) {
                RecordSpinner(diameter: 44)
            } else {
                Text(Glyph.radio)
                    .font(RPMFont.icon(40))
                    .foregroundStyle(RPMInk.white(0x3A / 255))

                Text(nothing)
                    .font(RPMFont.display(14))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nothing: String {
        if showingSaved {
            switch saved {
            case .mine: return Loc.get("Radio_NoFavorites")
            case .owners, .reading: return Loc.get("Radio_SharedNoFavorites")
            case .unreadable: return Loc.get("Radio_SharedFavoritesError")
            }
        }
        if genre != nil || country != nil { return Loc.get("Radio_NoFilterMatch") }
        return Loc.get("Radio_NoResults")
    }
}
