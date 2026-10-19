import Foundation
import CoreGraphics
import RPMKit

/// Pictures of the artist, for the screen that shows one behind the record.
///
/// Ported in shape from the backdrop part of `RPM.Mobile/Services/ArtworkService.cs`.
///
/// **This is the one thing in the app that is ever looked up by name.** A cover guessed from an artist and
/// a title can quietly be the wrong pressing, the wrong region, or another artist's record. Nothing on
/// screen says so. That is why ``ArtworkStore`` has no lookup by name at all. A wrong backdrop shows a
/// photograph of the wrong band, which the viewer can see and judge.
///
/// There are two caches, and they answer different questions. **Which pictures an artist has** is one
/// small answer per artist. It is kept for the session, so a track change inside an album does not ask
/// again. **The picture itself** is about a megabyte, so only a few are held, and the newest one wins.
///
/// **A photograph is cut for the frame it goes in.** See ``ArtFrame``. The frame is part of the question,
/// not something the view sorts out afterwards. What is held is the bytes as they arrived, plus the last
/// cut made from them. So turning the phone re-cuts for the new shape without asking the network again.
///
/// Every failure becomes "no picture": offline, signed out, an artist nobody has heard of, or a URL that
/// returns 404. In each case the record is drawn on its own background.
public actor BackdropStore {
    private let source: any ArtSource

    /// Which pictures an artist has, best first, in both shapes. The key is the artist alone. The pictures
    /// belong to the artist, and every album by them shows the same ones. Asking once per album would repeat
    /// the same question.
    ///
    /// Both lists come from the same answer and are never mixed. The backdrops are paged through
    /// ``ArtistPictures/backdrops`` and nothing else. Only ``portrait(artist:album:cutFor:)`` reads
    /// ``ArtistPictures/squares``.
    private var found: [String: ArtistPictures] = [:]

    /// One of the artist's photographs: what arrived, and the last window cut out of it.
    private struct Kept {
        let url: URL
        let bytes: Data
        var cut: (scene: ArtScene, fit: Fit, picture: CGImage)?
    }

    /// How a photograph is fitted to its frame. Every fetch states it. The backdrops and the squares are
    /// framed differently, and no URL says which list it came from.
    private enum Fit: Hashable {
        /// Read with Vision and cut so the face lands in the clear part of the screen. This is for the
        /// backdrops, which are taken for a wide screen with the person anywhere in the picture.
        case findTheFace

        /// Filled, centred across, and kept from the top, with nothing read. This is for the squares, which
        /// are already cut on the person. See ``ArtFrame/filled(_:for:widest:)``.
        case fillFromTop
    }

    /// The pictures themselves, newest first. The list is short. These are full-frame photographs, and a
    /// phone has better uses for its memory.
    private var held: [Kept] = []

    /// How many to keep: an artist's whole set of backdrops.
    ///
    /// The desktop's preselector ranks eight, and the stage lays out eight. Holding fewer would mean the far
    /// end of a set is downloaded again each time the user swipes back to it. Eight cut pictures take some tens
    /// of megabytes. That is the cost of a swipe that moves a photograph already on the screen.
    ///
    /// It also covers the chooser's shortlist, so nothing it has read is thrown away before the winner is shown.
    private static let keep = 8

    /// The picture each artist was left on. This is not cleared by ``forget()``. It is not the user's data. It
    /// is which photograph of an artist looks best on a phone, and that is true for whoever holds the phone next.
    private var picks: BackdropPicks

    /// How wide a backdrop is drawn. This is the long edge of a phone at three times scale, and no more. A
    /// backdrop is drawn full-bleed behind everything, so it needs the screen's own pixels and no more.
    public static let width = 1400

    /// The width a backdrop is decoded at in order to be *read* by Vision. This is a different number, and a
    /// bigger one. The crop keeps only a fraction of the picture, so a photograph decoded at the size it will
    /// be shown has already thrown away the pixels the zoom would need. Most backdrops arrive at about this
    /// size, so for most of them nothing is lost.
    public static let read = 2048

    /// - Parameter picking: where the picks are written. The usual location is used unless a test says otherwise.
    ///   A test must not write into the user's own Documents folder.
    public init(source: any ArtSource, picking: URL? = nil) {
        self.source = source
        picks = picking.map(BackdropPicks.init(file:)) ?? .inDocuments()
    }

    /// The picture to show behind this artist, or nil where there is none.
    ///
    /// - Parameters:
    ///   - at: which of the artist's pictures. A caller that pages through them asks for the next one this way.
    ///     An index out of range returns nil rather than wrapping around. A set that wrapped would page forever
    ///     through one photograph.
    ///   - cutFor: the frame it is going on, and what covers it. **This is not optional.** A photograph handed
    ///     over uncut often has a face behind the record. A default would hide the caller forgetting to say
    ///     which screen this is.
    public func backdrop(artist: String?, album: String?, at: Int = 0,
                         cutFor scene: ArtScene) async -> CGImage? {
        guard let artist, !artist.isEmpty, at >= 0 else { return nil }

        let urls = await pictures(of: artist, album: album).backdrops
        guard at < urls.count else { return nil }

        return await fetch(urls[at], cutFor: scene, fit: .findTheFace)
    }

    /// A picture of this artist for a page about them: the home banner's card and the band on the artist page.
    /// It is cut for that frame, like a backdrop.
    ///
    /// **The square comes first.** fanart.tv's square artist pictures (1000 by 1000) are framed on the person.
    /// If the artist has one, it is the picture. If the artist has none, or it will not download, the first
    /// backdrop is used instead. Squares are used on home and the artist page only, not on the wall's boxes
    /// and not behind the record.
    ///
    /// **A square is not read.** It is filled into the frame, centred across, and kept from the top. Only a
    /// backdrop is read with Vision, to find where the face is. The square is already framed on the person,
    /// and reading it again would only zoom in further.
    ///
    /// **A square is not used if its face would be behind the status bar.** The square is kept from the top.
    /// So on a frame that runs up behind the status bar (``ArtScene/clearTop``), a face high in the square can
    /// land behind the Dynamic Island. Each of the first few squares is read for its faces. The first one whose
    /// main face is clear is the picture. If none is clear, the first backdrop is used, which is cut to put its
    /// face in the clear. A square with a covered face is used only when there is nothing else.
    ///
    /// This is not part of the set. ``backdrop(artist:album:at:cutFor:)`` indexes the backdrops only. A square
    /// can therefore never be paged to on the stage, or remembered as the artist's pick.
    public func portrait(artist: String?, album: String?, cutFor scene: ArtScene) async -> CGImage? {
        guard let artist, !artist.isEmpty else { return nil }

        let ask = PortraitAsk(artist: artist, scene: scene)
        if let settled = portraits[ask] {
            return await fetch(settled.url, cutFor: scene, fit: settled.fit)
        }

        let said = await pictures(of: artist, album: album)

        // Whether every square looked at so far was read. A square that will not download, or that Vision cannot
        // read, is not known to be clear. A choice made after such a square is not saved. The next request reads
        // it again.
        var allRead = true
        var covered: URL?

        for square in said.squares.prefix(Self.squaresRead) {
            guard let data = await bytes(square),
                  let photograph = Thumbnail.of(data, edge: Self.read) else {
                allRead = false
                continue
            }

            let reading = PhotoVision.faces(photograph)
            if reading == nil { allRead = false }

            if let reading,
               ArtFrame.coversFace(reading.faces, width: reading.width, height: reading.height,
                                   for: scene) {
                covered = covered ?? square
                continue
            }

            let picture = ArtFrame.filled(photograph, for: scene, widest: Self.width)
                ?? Thumbnail.of(data, edge: Self.width)
            guard let picture else { continue }

            keep(square, bytes: data, cut: (scene, .fillFromTop, picture))
            if allRead { portraits[ask] = Portrait(url: square, fit: .fillFromTop) }
            return picture
        }

        if let backdrop = said.backdrops.first,
           let picture = await fetch(backdrop, cutFor: scene, fit: .findTheFace) {
            if allRead { portraits[ask] = Portrait(url: backdrop, fit: .findTheFace) }
            return picture
        }

        // Nothing else to show. This is not saved. A backdrop that did not download this time may download next
        // time, and it is the better picture.
        guard let covered else { return nil }
        return await fetch(covered, cutFor: scene, fit: .fillFromTop)
    }

    /// How many of an artist's squares are read for where the face is. Each one read is one download, on the
    /// user's data. This uses the chooser's own limit.
    private static let squaresRead = BackdropChooser.maxCandidates

    /// The picture ``portrait(artist:album:cutFor:)`` settled on for an artist, on a frame. This means the
    /// squares are read once per session, not once per card.
    private var portraits: [PortraitAsk: Portrait] = [:]

    private struct PortraitAsk: Hashable {
        let artist: String
        let scene: ArtScene
    }

    private struct Portrait {
        let url: URL
        let fit: Fit
    }

    /// Chooses which of this artist's photographs to open on.
    ///
    /// Use the photograph the user last left the artist on, if there is one. Otherwise pick the best of the
    /// first few. The best is judged by **what its crop would actually look like** on this frame. That verdict
    /// is saved, so the judging runs once per artist, not once per record.
    ///
    /// The saved pick is kept whatever shape the frame is. A photograph picked by hand is the user's answer to
    /// "which picture of them". Turning the phone does not change that question. Only the cut changes, and the
    /// cut is decided again anyway.
    public func opening(artist: String?, album: String?, cutFor scene: ArtScene) async -> Opening {
        guard let artist, !artist.isEmpty else { return .init(at: 0, of: 0, fetched: 0, decoded: 0, judged: 0, weighed: 0, why: "nobody") }
        guard scene.isLaidOut else { return .init(at: 0, of: 0, fetched: 0, decoded: 0, judged: 0, weighed: 0, why: "no frame yet") }

        let urls = await pictures(of: artist, album: album).backdrops
        guard urls.count > 1 else {
            return .init(at: 0, of: urls.count, fetched: 0, decoded: 0, judged: 0, weighed: 0, why: "nothing to choose from")
        }

        if let picked = picks.pick(artist), let at = urls.firstIndex(of: picked) {
            return .init(at: at, of: urls.count, fetched: 0, decoded: 0, judged: 0, weighed: 0, why: "remembered")
        }

        var bestAt = 0
        var best = -Double.infinity
        var fetched = 0, decoded = 0, judged = 0, weighed = 0

        for at in 0..<min(urls.count, BackdropChooser.maxCandidates) {
            guard let data = await bytes(urls[at]) else { continue }
            fetched += 1
            weighed += data.count

            guard let photograph = Thumbnail.of(data, edge: Self.read) else { continue }
            decoded += 1

            guard let verdict = BackdropChooser.judge(photograph, for: scene,
                                                      widest: Self.width, needing: Self.width)
            else { continue }

            // The cut is already made, so it is kept. The winner is shown without being read a second time, and
            // the runners-up are the neighbours a swipe will want.
            keep(urls[at], bytes: data, cut: (scene, .findTheFace, verdict.picture))
            judged += 1

            if verdict.score > best {
                best = verdict.score
                bestAt = at
            }
        }

        // **A decision that could not be made is not saved.** Nothing could be read here, because there was no
        // network or the device's Vision model did not start. Saving "picture 0" would settle the artist for good
        // on an answer that nobody reached. Left unsaved, the next launch judges the artist again.
        guard judged > 0 else {
            return .init(at: 0, of: urls.count, fetched: fetched, decoded: decoded,
                         judged: 0, weighed: weighed, why: "nothing could be read")
        }

        picks.remember(urls[bestAt], for: artist)
        return .init(at: bestAt, of: urls.count, fetched: fetched, decoded: decoded,
                     judged: judged, weighed: weighed, why: "judged")
    }

    /// The chosen photograph, and how that choice was reached.
    ///
    /// The reason is returned with the answer, because each reason is a different event. From outside they all
    /// look the same. An artist with one photograph, an artist judged just now, an artist whose pick was read from
    /// the disk, and a frame that is not laid out yet all return index 0.
    public struct Opening: Sendable {
        public let at: Int

        /// How many photographs the artist has, how many were downloaded, and how many of those could be read.
        /// The three counts fail in different ways, and from outside they look the same. Nobody has any, the
        /// download failed, or Vision could not read them.
        public let of: Int, fetched: Int, decoded: Int, judged: Int

        /// How many bytes those downloads were. This one number separates "the store did not return the data"
        /// from "the data arrived but could not be decoded".
        public let weighed: Int

        /// The reason in plain words, for the diagnostic line on the stage.
        public let why: String
    }

    /// Records where the user left this artist. The user moved there by hand.
    ///
    /// **This records the landing, not the load.** Photographs on either side of the one on screen are fetched
    /// long before the user reaches them. A pick saved for one nobody has seen would make a photograph the user
    /// never saw into the artist's pick.
    public func remember(artist: String?, album: String?, at: Int) async {
        guard let artist, !artist.isEmpty else { return }

        let urls = await pictures(of: artist, album: album).backdrops
        guard at >= 0, at < urls.count else { return }

        picks.remember(urls[at], for: artist)
    }

    /// The artist's logo for the title of their page. It is cut to its lettering and reduced to fit `box`. Nil
    /// if the artist has no logo or it could not be fetched. See ``Lettering``.
    ///
    /// The mark is fetched and trimmed once per address, then kept. Only the reduction is done again for a new
    /// box. A logo that does not download or decode is not kept, so the next request tries again. The desktop's
    /// `ArtistLogos` works the same way.
    public func logo(artist: String?, album: String?, box: LetteringBox) async -> CGImage? {
        guard let artist, !artist.isEmpty, box.tall > 0 else { return nil }
        guard let url = await pictures(of: artist, album: album).logo else { return nil }

        let mark: CGImage
        if let kept = marks.first(where: { $0.url == url }) {
            mark = kept.mark
        } else {
            guard let data = try? await source.artwork(at: url),
                  let decoded = Lettering.decode(data) else { return nil }

            mark = Lettering.trimmed(decoded)
            marks.insert((url, mark), at: 0)
            if marks.count > Self.keep { marks.removeLast(marks.count - Self.keep) }
        }

        return Lettering.fitted(mark, height: Lettering.height(of: mark, cap: box.tall,
                                                               room: box.wide))
    }

    /// Logos already fetched and trimmed, newest first. A logo is about a megabyte once decoded.
    private var marks: [(url: URL, mark: CGImage)] = []

    /// How many pictures this artist has. Zero is the normal answer for an artist with none.
    public func count(artist: String?, album: String?) async -> Int {
        guard let artist, !artist.isEmpty else { return 0 }

        return await pictures(of: artist, album: album).backdrops.count
    }

    /// Clears everything. Used on sign-out, and on sign-in as a different user. A phone that is handed on must
    /// not still hold the last person's pictures.
    public func forget() {
        found = [:]
        held = []
        portraits = [:]
        marks = []
    }

    // ── the lookup ──

    /// Lookups in progress, by artist. A second request for the same artist, made while the first is still
    /// running, waits for it.
    private var asking: [String: Task<ArtistPictures?, Never>] = [:]

    private func pictures(of artist: String, album: String?) async -> ArtistPictures {
        let key = artist.lowercased()
        if let known = found[key] { return known }

        // One request per artist at a time. The artist page asks for the photograph and the logo as it opens.
        // Both arrive here before either answer is back.
        if let running = asking[key] { return await running.value ?? .none }

        // **An answer is cached. A failure is not.** Caching an empty answer is the point. An artist with no
        // photograph anywhere is common, and without the cache every track change would ask the catalogue about
        // them again. Caching a failure is the opposite. A lookup made before the phone finished signing in would
        // be taken as "this artist has no photographs", and believed for the rest of the session.
        let source = self.source
        let ask = Task { try? await source.artistPictures(artist: artist, album: album) }
        asking[key] = ask
        let answer = await ask.value
        asking[key] = nil

        guard let said = answer else { return .none }

        // A partial answer is not kept either. The API marks it as unfinished. If it were kept for the session, it
        // would stand in for the whole answer until the app restarts.
        if !said.partial {
            found[key] = said
        }
        return said
    }

    // ── the picture ──

    private func fetch(_ url: URL, cutFor scene: ArtScene, fit: Fit) async -> CGImage? {
        if let at = held.firstIndex(where: { $0.url == url }) {
            // Already cut for this exact frame and fit. This is the usual case, because the frame only changes
            // when the phone turns.
            if let cut = held[at].cut, cut.scene == scene, cut.fit == fit { return cut.picture }

            guard let picture = frame(held[at].bytes, cutFor: scene, fit: fit) else { return nil }

            held[at].cut = (scene, fit, picture)
            return picture
        }

        guard let data = await bytes(url),
              let picture = frame(data, cutFor: scene, fit: fit) else { return nil }

        keep(url, bytes: data, cut: (scene, fit, picture))
        return picture
    }

    /// One photograph's bytes, from what is held or from the network.
    private func bytes(_ url: URL) async -> Data? {
        if let at = held.firstIndex(where: { $0.url == url }) { return held[at].bytes }

        return try? await source.artwork(at: url)
    }

    private func keep(_ url: URL, bytes: Data, cut: (scene: ArtScene, fit: Fit, picture: CGImage)) {
        if let at = held.firstIndex(where: { $0.url == url }) {
            held[at].cut = cut
            return
        }

        held.insert(Kept(url: url, bytes: bytes, cut: cut), at: 0)
        if held.count > Self.keep { held.removeLast(held.count - Self.keep) }
    }

    /// Decodes and cuts the photograph. It is read first where the fit asks for the face, and filled from the
    /// top where it does not.
    ///
    /// If Vision refuses the photograph, or finds no face in it, the photograph is still shown. It is cut and kept
    /// from the top, where a person's head usually is. Uncut, a view fills its frame from the middle. On a frame
    /// much wider than the photograph, such as the TV's home banner, the middle is often a person's chest. The
    /// photograph is shown as it came only when it cannot be cut at all.
    private func frame(_ data: Data, cutFor scene: ArtScene, fit: Fit) -> CGImage? {
        guard let photograph = Thumbnail.of(data, edge: Self.read) else { return nil }

        let cut: CGImage?
        switch fit {
        case .findTheFace:
            cut = ArtFrame.cut(photograph, for: scene, widest: Self.width)
                ?? ArtFrame.filled(photograph, for: scene, widest: Self.width)
        case .fillFromTop: cut = ArtFrame.filled(photograph, for: scene, widest: Self.width)
        }

        return cut ?? Thumbnail.of(data, edge: Self.width)
    }
}

/// The space a logo is fitted into, in pixels: at most `tall` high and `wide` across. A `wide` of zero means
/// the width is not known yet. Then only the height limits the logo.
public struct LetteringBox: Hashable, Sendable {
    public let tall: Int
    public let wide: Int

    public init(tall: Int, wide: Int) {
        self.tall = tall
        self.wide = wide
    }
}
