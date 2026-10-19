import SwiftUI
import RPMKit

/// What rpm is, and everything on this phone that somebody else made.
///
/// Raised as a sheet from the About card on ``ProfilePage`` rather than living on the tab: it is
/// read once, by somebody who went looking for it, and the tab is where the account and the
/// playback settings are.
///
/// **The list is shorter than the desktop's and that is correct.** This app is Swift against
/// Apple's own frameworks and carries no third-party code at all, so what is credited is the
/// typefaces it draws with and the services it calls. See ``Credits``.
///
/// Two states in one sheet, as in the desktop dialog: the list, and one licence in full.
/// A `NavigationStack` is not used here, because it paints its own opaque background over the
/// ground this app is drawn on.
public struct AboutPage: View {
    private let version: String
    private let onClose: () -> Void

    /// The licence being read, with the entry it belongs to, or nil for the list. One value rather
    /// than a flag and two others, so there is no state in which the sheet is reading a licence it
    /// cannot name the holder of.
    @State private var reading: Reading?

    @Environment(\.openURL) private var openUrl

    private struct Reading: Equatable {
        let entry: CreditEntry
        let licence: CreditLicense
        let text: String
    }

    public init(version: String, onClose: @escaping () -> Void) {
        self.version = version
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            RPMInk.ground.ignoresSafeArea()

            if let reading {
                licence(reading)
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top) { bar }
    }

    // ── the bar ──

    /// One key, and it means Back while a licence is open. A second key that does nothing most of
    /// the time looks broken.
    private var bar: some View {
        HStack {
            Button(reading == nil ? Loc.get("About_Close") : Loc.get("About_Back")) {
                if reading == nil { onClose() } else { reading = nil }
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 34,
                                        stretches: false, inset: 16, size: 13))

            Spacer()

            Text(reading == nil ? Loc.get("About_Title") : Loc.get("About_License"))
                .rpmKicker()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // ── the list ──

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                identity

                VStack(alignment: .leading, spacing: 6) {
                    Text(Loc.get("About_Acknowledgements"))
                        .font(RPMFont.displayBold(17))
                        .foregroundStyle(RPMInk.white(1))

                    Text(Loc.get("About_Intro"))
                        .font(RPMFont.display(12.5))
                        .foregroundStyle(RPMInk.white(0x99 / 255))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Credits.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Loc.get(section.title))
                                .font(RPMFont.displayBold(14))
                                .foregroundStyle(RPMInk.white(0xE0 / 255))

                            if let note = section.note {
                                Text(Loc.get(note))
                                    .font(RPMFont.display(12))
                                    .foregroundStyle(RPMInk.white(0x88 / 255))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("rpm")
                .font(RPMFont.header(34))
                .foregroundStyle(RPMInk.white(0xCC / 255))

            Text(Loc.get("About_Tagline"))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xB3 / 255))

            Text("\(Loc.get("About_Version", version))  ·  © \(year) rpm. \(Loc.get("About_Rights"))")
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x66 / 255))
                .padding(.top, 4)

            // One row where the four labels fit, two rows where they do not (French and Spanish are
            // wider than the screen on a small phone).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    key(Loc.get("About_Website"), RpmSite.home)
                    key(Loc.get("About_Support"), RpmSite.support)
                    key(Loc.get("About_Privacy"), RpmSite.privacy)
                    key(Loc.get("About_Terms"), RpmSite.terms)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        key(Loc.get("About_Website"), RpmSite.home)
                        key(Loc.get("About_Support"), RpmSite.support)
                    }
                    HStack(spacing: 8) {
                        key(Loc.get("About_Privacy"), RpmSite.privacy)
                        key(Loc.get("About_Terms"), RpmSite.terms)
                    }
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .rpmSection()
    }

    private var year: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    private func key(_ title: String, _ url: URL) -> some View {
        Button(title) { openUrl(url) }
            .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 30,
                                        stretches: false, inset: 12, size: 12))
    }

    // ── one entry ──

    private func row(_ entry: CreditEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(entry.name)
                    .font(RPMFont.display(13.5))
                    .foregroundStyle(RPMInk.white(0xF0 / 255))

                if let version = entry.version {
                    faint(version)
                }
                if let detail = entry.detail {
                    faint(detail)
                }
            }

            if let use = entry.use {
                Text(Loc.get(use))
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x99 / 255))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let copyright = entry.copyright {
                Text(copyright)
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x66 / 255))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Wrapped, because a row can carry four of these and a phone is 390 points wide.
            FlowRow(spacing: 14, lineSpacing: 4) {
                ForEach(entry.licenses, id: \.self) { name in
                    if let licence = Credits.licenses[name] {
                        // A licence whose text ships opens here. One that does not is a published
                        // set of terms only its publisher may host, so it opens in Safari, and the
                        // row says which by where it sends you rather than by explaining. A notices
                        // document ships and still opens in Safari: it is hundreds of kilobytes of
                        // licences, and this reader puts a text in one block.
                        if licence.file != nil, !licence.isNotices {
                            link(licence.name, Glyph.license) { read(entry, licence) }
                        } else {
                            link(licence.name, Glyph.outward) {
                                open(entry.termsUrl ?? licence.url)
                            }
                        }
                    }
                }

                if let url = entry.url, !url.isEmpty {
                    link(host(url), Glyph.link) { open(url) }
                }
                if let source = entry.source, !source.isEmpty {
                    link(Loc.get("About_SourceCode"), Glyph.code) { open(source) }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RPMInk.white(0x0E / 255), in: RoundedRectangle(cornerRadius: 10))
    }

    private func faint(_ text: String) -> some View {
        Text(text)
            .font(RPMFont.display(11.5))
            .foregroundStyle(RPMInk.white(0x66 / 255))
    }

    private func link(_ title: String, _ glyph: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack(spacing: 5) {
                Text(glyph)
                    .font(RPMFont.icon(10))
                    .foregroundStyle(RPMInk.white(0x77 / 255))
                Text(title)
                    .font(RPMFont.display(11.5))
                    .foregroundStyle(RPMInk.white(0xCC / 255))
            }
        }
        .buttonStyle(.plain)
    }

    /// A link's label: the site, not the address. A full URL in eleven-point type on a phone is a
    /// line that is hard to read and will not fit anyway.
    private func host(_ url: String) -> String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // ── one licence ──

    private func licence(_ reading: Reading) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reading.licence.name)
                        .font(RPMFont.displayBold(17))
                        .foregroundStyle(RPMInk.white(1))

                    Text(reading.entry.copyright.map { "\(reading.entry.name). \($0)" }
                         ?? reading.entry.name)
                        .font(RPMFont.display(12.5))
                        .foregroundStyle(RPMInk.white(0x99 / 255))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Monospaced, and the only place in the app that is. A licence is a legal text with
                // its own line breaks and its own indentation, and setting it in the app's face
                // re-wraps paragraphs written to a fixed measure.
                Text(reading.text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(RPMInk.white(0xCC / 255))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    /// Reads the licence and switches to it in one step, so the sheet cannot be on the reader with
    /// nothing in it. The files are a few kilobytes off the app bundle; there is nothing here worth
    /// a spinner and a second state.
    @MainActor
    private func read(_ entry: CreditEntry, _ licence: CreditLicense) {
        reading = Reading(entry: entry, licence: licence,
                          text: Credits.text(of: licence, copyright: entry.copyright))
    }

    private func open(_ url: String?) {
        guard let url, let address = URL(string: url) else { return }
        openUrl(address)
    }
}
