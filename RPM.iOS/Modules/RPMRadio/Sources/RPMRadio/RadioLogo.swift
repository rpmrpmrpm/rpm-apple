import Foundation

/// Whether a station's published logo can actually be drawn, and which of several logos to try
/// first.
///
/// Ported from `RPM.Core/Radio/RadioLogo.cs`. A directory entry's favicon is a URL that someone
/// typed years ago. A good half of them are the broadcaster's site favicon. Most image decoders
/// cannot open those, so they draw as nothing. Two places must agree on this. The view that shows
/// the logo needs it, so it can show the antenna icon instead of an empty space. ``RadioResults``
/// also needs it, when it merges a station's several entries into one. "Has a logo" must mean "has
/// a logo that will appear". Otherwise the merge keeps a .ico file from the high-bitrate stream,
/// counts it as a logo, and drops the real PNG from the 32k copy.
///
/// The desktop's `Native` and `IsVector` are not here. They belong to that app's image loader. That
/// loader asks a resizing host for an asset's own size, and it chooses between a bitmap source and
/// an SVG source. This app fetches through `SmallPictures` and moves on from anything that does not
/// decode, SVG included.
public enum RadioLogo {
    /// Whether this is a URL worth giving to an image decoder.
    ///
    /// One thing is rejected, and it is not a judgement about the picture: an address that is not
    /// http or https. A dead link cannot be told from a live one without fetching it, so that is
    /// not checked here. The view that tries the link reports back and moves on to the next logo
    /// the station has.
    public static func isDrawable(_ favicon: String?) -> Bool {
        guard let favicon, !favicon.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: favicon), let scheme = url.scheme?.lowercased()
        else { return false }

        // A URL with no host parses without error, but it is not an address. "/relative/logo.png"
        // has no scheme. "https:logo.png" has a scheme, but no host.
        return (scheme == "http" || scheme == "https") && !(url.host ?? "").isEmpty
    }

    /// How likely this URL is to become a picture. It is used to choose which logo to try first.
    ///
    /// This is a guess, and only a guess. Whether a host will serve a file can only be known by
    /// asking it. The view that asks is what settles it. This value only sets the order of the
    /// requests. So a wrong guess costs one failed request, not a blank row. Nothing is ever
    /// excluded by it. A station whose only logo scores badly is still tried. The other choice
    /// would be a maintained list of hosts that decides a broadcaster has no picture.
    ///
    /// - Parameter homepage: the station's own site. A logo served from that site is the
    ///   broadcaster's own
    ///   copy of their own mark. This is the best signal there is. The third-party mirrors are
    ///   where the broken links and refusals are.
    public static func rank(_ favicon: String?, homepage: String?) -> Int {
        guard let favicon, let url = URL(string: favicon), !(url.host ?? "").isEmpty
        else { return Int.min }

        var score = 0

        let host = site(url)
        if !host.isEmpty {
            if let home = homepage.flatMap({ URL(string: $0) }), site(home) == host {
                score += ownSite
            }
            if hotlinkers.contains(host) {
                score += refusesHotlinks
            }
        }

        // Only the path is used, not the whole address. A query string does not make a picture a
        // site icon. Nor does "favicon.ico" inside one.
        let path = url.path.lowercased()
        if keepsAlpha.contains(where: path.hasSuffix) {
            score += canBeTheMark
        } else if path.hasSuffix(".svg") {
            score += isADrawing
        } else if flattened.contains(where: path.hasSuffix) {
            score += isAPicture
        } else if path.hasSuffix(".ico") {
            score += isASiteIcon
        }

        // A host that cuts to order gives whatever size the surface asks for. So the size in its
        // address says nothing about the picture. Against a candidate that gives the one size
        // somebody happened to upload, that is worth having. This score is set below the
        // broadcaster's own site on purpose. A broadcaster's own copy of their mark is a better
        // answer than a resizable mirror of somebody's guess at it.
        if cutsToOrder(favicon) {
            score += anySize
        }

        // This is not about the picture. A plain http logo is the one that a strict host, or a
        // future policy against cleartext, drops. When two copies of one mark differ only in
        // scheme, there is no reason to pick the weaker one.
        if url.scheme?.lowercased() == "https" {
            score += overHttps
        }

        return score
    }

    /// Whether this host cuts a picture to whatever size is asked for. So the size in the address
    /// says nothing about how good the picture is. ``rank(_:homepage:)`` prefers these hosts when
    /// two candidates are otherwise equal. One of these hosts gives a surface what it needs. The
    /// other gives the one size somebody happened to upload.
    public static func cutsToOrder(_ url: String?) -> Bool {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return false }
        return host == "i.iheart.com" || host == "static.wixstatic.com"
            || host == "cdn-profiles.tunein.com"
    }

    /// The address with the size taken out, so two spellings of one picture can be told apart from
    /// two different pictures.
    ///
    /// A station's entries often name the same asset at three sizes. They also often name three
    /// different assets. These are not the same situation. The first is one mark that its
    /// contributors agree on. The second is a disagreement about which mark it is. Keyed on this
    /// value, the agreement can be counted rather than guessed. See ``RadioResults``.
    public static func samePicture(_ url: String?) -> String {
        guard let url else { return "" }
        guard cutsToOrder(url) else { return url }

        // "$1" keeps Wix's verb, which is part of the address rather than part of the size. "fill"
        // crops and "fit" letterboxes. Two entries that ask for one asset in two ways are not
        // asking for one picture.
        var bare = strip(url, iHeartBox, "contain()")
        bare = strip(bare, wixBox, "$1/w_,h_")
        return strip(bare, tuneInLogo, "/images/logo.")
    }

    private static func strip(_ text: String, _ pattern: NSRegularExpression,
                              _ with: String) -> String {
        pattern.stringByReplacingMatches(in: text,
                                         range: NSRange(text.startIndex..., in: text),
                                         withTemplate: with)
    }

    // ── the size the address itself asks for ──

    /// The same mark asked for at `edge` pixels or more, where the host takes a size in the
    /// address. Otherwise the address is returned exactly as it came.
    ///
    /// **What is wrong with these addresses.** A directory entry's logo is the address of a picture
    /// at one size. The size is whatever the person who filed the entry pasted. iHeart's addresses
    /// are the plainest case. One station's streams carry the same asset filed as `contain(32,32)`
    /// under one, and as `contain(360,360)` under another. The row showed whichever size the merge
    /// kept. Thirty-two pixels stretched into a forty-point well gives the blocky logo that this
    /// function is for. The picture was never the problem. Of the thousand American stations the
    /// directory ranks highest, 192 are on that one host, and 42 of those ask for 32 pixels.
    ///
    /// **Up only, never down.** One address is fetched by a row that needs forty points, and by the
    /// player's tile that needs several hundred. A rewrite that trimmed a large address to the
    /// row's size would give the small logo on the larger surface.
    ///
    /// **It cannot add detail.** These hosts resample rather than refuse. So a small asset comes
    /// back large and soft. That is not a reason to ask for less. It is the same picture either
    /// way, and most of the pictures do have the pixels.
    ///
    /// There are three families, each read off the directory's own answers. Everything else is
    /// returned unchanged, which is the usual case.
    public static func sized(_ url: String?, edge: Int) -> String? {
        guard let url, edge > 0, let host = URL(string: url)?.host?.lowercased()
        else { return url }

        switch host {
        case "i.iheart.com": return raise(url, iHeartBox, edge, w: 1, h: 2)
        case "static.wixstatic.com": return raise(url, wixBox, edge, w: 2, h: 3)
        case "cdn-profiles.tunein.com": return tuneIn(url, edge)
        case "upload.wikimedia.org", "thumb.wikimedia.org": return wikimedia(url, edge)
        default: return url
        }
    }

    /// A Wikimedia thumbnail, asked for at a width that Wikimedia will serve.
    ///
    /// **Wikimedia does not render to order.** A thumbnail URL carries a width, and Wikimedia
    /// answers 400 to every width outside a fixed list. Measured against three files, identical
    /// each time: 120, 250 and 500 are served. 80, 160, 180, 220, 320, 400, 512, 640, 800, 1024 and
    /// 1200 are refused. The directory has many 640px and 1200px addresses. Those are sizes that
    /// somebody's browser asked for years ago, and every one of them is a dead link.
    ///
    /// The 400 error comes from the size, not from a refusal to serve the app. Of the 29 Wikimedia
    /// logos in the 1,500 most-clicked stations, 15 load exactly as filed.
    ///
    /// This takes the largest rung that is not bigger than the request, so it never enlarges a
    /// request. A request under 120 still gets 120, because nothing smaller is available.
    private static func wikimedia(_ url: String, _ edge: Int) -> String {
        guard let box = try? NSRegularExpression(pattern: "/(?:lang[a-z-]+-)?([0-9]{1,5})px-",
                                                 options: .caseInsensitive),
              let m = box.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let width = Range(m.range(at: 1), in: url)
        else { return url }

        let rung = wikimediaLadder.last(where: { $0 <= edge }) ?? wikimediaLadder[0]
        return url.replacingCharacters(in: width, with: String(rung))
    }

    /// The widths that Wikimedia renders a thumbnail at, smallest first. These were read from the
    /// host. The same three were found for every file tried.
    private static let wikimediaLadder = [120, 250, 500]

    /// The largest size that any of these is ever asked for. The player's tile is the largest
    /// surface on which a station's mark is drawn. It is a mark, not a scan. Above this size the
    /// request costs more than the screen can show.
    private static let ceiling = 1024

    /// A width-and-height box in an address, scaled so its short side reaches `edge`.
    ///
    /// Both sides use the same factor. This is not a nicety. The box these hosts take is also a
    /// crop. Wix's `fill/` cuts the picture to the shape it is given. So squaring a wordmark's box
    /// would cut the ends off the name. What is wanted is the picture that the entry already
    /// describes, at a larger size.
    private static func raise(_ url: String, _ box: NSRegularExpression, _ edge: Int,
                              w: Int, h: Int) -> String {
        guard let match = box.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              // Asking for a group that the pattern does not have raises an error instead of
              // returning a result. So the count is checked before either range is read.
              match.numberOfRanges > max(w, h),
              let wide = Range(match.range(at: w), in: url),
              let tall = Range(match.range(at: h), in: url),
              let width = Int(url[wide]), let height = Int(url[tall]),
              width > 0, height > 0
        else { return url }

        // The factor never goes past the ceiling. The ceiling is measured on the long side, which
        // is the side that decides what the request weighs.
        let factor = min(Double(edge) / Double(min(width, height)),
                         Double(ceiling) / Double(max(width, height)))
        guard factor > 1 else { return url }   // The address already asks for enough.

        // The later number is written first, so writing it cannot move the earlier one's range out
        // from under it.
        let (first, firstTo) = wide.lowerBound < tall.lowerBound ? (wide, width) : (tall, height)
        let (last, lastTo) = wide.lowerBound < tall.lowerBound ? (tall, height) : (wide, width)

        var raised = url
        raised.replaceSubrange(last, with: String(Int((Double(lastTo) * factor).rounded())))
        raised.replaceSubrange(first, with: String(Int((Double(firstTo) * factor).rounded())))
        return raised
    }

    /// TuneIn does not take a size. It takes one of four letters, and this function picks which
    /// one. It picks the smallest letter that covers the request. If the letter already in the
    /// address covers it, the address is left alone. Going the other way would be a downgrade made
    /// to look like a fit.
    private static func tuneIn(_ url: String, _ edge: Int) -> String {
        guard let match = tuneInLogo.firstMatch(in: url,
                                                range: NSRange(url.startIndex..., in: url)),
              let markRange = Range(match.range(at: 1), in: url),
              let mark = url[markRange].lowercased().first
        else { return url }

        if let now = ladder.first(where: { $0.mark == mark }), now.edge >= edge { return url }

        let wanted = ladder.first { $0.edge >= edge } ?? ladder[ladder.count - 1]
        var raised = url
        raised.replaceSubrange(markRange, with: String(wanted.mark))
        return raised
    }

    /// How many pixels each of TuneIn's letters gives, smallest first. These were read from the
    /// host. The same station's `logot`, `logoq`, `logod` and `logog` come back at 75, 145, 300 and
    /// 600 pixels square.
    private static let ladder: [(mark: Character, edge: Int)] =
        [("t", 75), ("q", 145), ("d", 300), ("g", 600)]

    // ── what each signal is worth ──

    /// Served from the broadcaster's own site.
    private static let ownSite = 4

    /// Served from a host that refuses to serve the app. The score is enough to put such a
    /// candidate below one with nothing going for it. It is not enough to put it below an
    /// unreadable one.
    private static let refusesHotlinks = -8

    /// Served by a host that cuts the mark to whatever size is wanted. See ``cutsToOrder(_:)``.
    private static let anySize = 3

    /// A format that can hold a mark and nothing else: a PNG or a WebP with an alpha channel.
    ///
    /// **Why the format is ranked at all.** A station's mark is drawn in a small dark well. What it
    /// needs is the mark with nothing behind it. A JPEG cannot give that, because the format has no
    /// alpha channel. So a JPEG arrives as a white or coloured rectangle in a dark rounded well.
    /// The result looks like a badge that failed to load, not a station's mark. Where a
    /// broadcaster's entries name the same mark as a PNG and as a JPEG, and they often do, the PNG
    /// is worth asking for first.
    private static let canBeTheMark = 2

    /// A drawing renders on the desktop app, through a second image source and a rasterize step. So
    /// a raster copy of the same mark is the better first try. On this platform a bitmap decoder
    /// cannot read a drawing at all. The fall-through handles that, at the cost of one request.
    private static let isADrawing = 1

    /// A format with no alpha channel, and nothing else to say for it. It will draw. It is level
    /// with an address that states no format at all. That is the usual shape of a CDN URL, and such
    /// an address is a PNG about as often as not.
    private static let isAPicture = 0

    /// A site's own favicon. It is a browser-tab icon, which is the station's mark at 32 pixels. It
    /// is a picture that exists, drawn soft. It is better than the antenna only because there is
    /// nothing else.
    private static let isASiteIcon = -1

    private static let overHttps = 1

    /// Hosts that will not serve an image to something that is not a browser. A match lowers the
    /// score (see ``refusesHotlinks``) but never excludes a logo. So a host that starts serving the
    /// app again works again after one failed request.
    ///
    /// The set is empty. Wikimedia is not listed. With the app's own User-Agent, 15 of the 29
    /// Wikimedia logos in the 1,500 most-clicked stations load exactly as the directory files them.
    /// The rest load once the width is snapped to one that Wikimedia renders (see
    /// ``wikimedia(_:_:)``). Listing it would sink a working logo below a dead link.
    ///
    /// The set is kept so that the next host that does this has somewhere to go.
    private static let hotlinkers: Set<String> = []

    /// Raster formats with an alpha channel. See ``canBeTheMark``.
    private static let keepsAlpha = [".png", ".webp"]

    /// Raster formats without one. GIF has one bit of transparency. That gives a hard edge, not a
    /// mark's soft antialiased edge. Nothing files a station's logo as a GIF on purpose.
    private static let flattened = [".jpg", ".jpeg", ".gif", ".bmp"]

    /// The host with "www." removed. This means a broadcaster's logo is recognised as their own,
    /// whichever way the directory spelled their address that day. The entries for one station can
    /// carry "nporadio1.nl" and "www.nporadio1.nl" in the same answer.
    private static func site(_ url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // ── the size an address asks for, where the host takes one ──

    /// iHeart: `?ops=...,contain(360,360),...`
    private static let iHeartBox = try! NSRegularExpression(
        pattern: #"contain\((\d{1,5}),(\d{1,5})\)"#, options: [.caseInsensitive])

    /// Wix: `.../v1/fill/w_455,h_413,al_c,...`. The pattern is anchored on the verb. The segment
    /// before it can carry a `w_` and an `h_` of its own, as in `/v1/crop/x_24,y_30,w_555,h_544/`.
    /// Those are source pixels. Rewriting them would move the crop, not resize the picture.
    private static let wixBox = try! NSRegularExpression(
        pattern: #"(fill|fit)/w_(\d{1,5}),h_(\d{1,5})"#, options: [.caseInsensitive])

    /// TuneIn: `.../images/logod.png`
    private static let tuneInLogo = try! NSRegularExpression(
        pattern: #"/images/logo([a-z])\.(?:png|jpe?g|webp)"#, options: [.caseInsensitive])
}
