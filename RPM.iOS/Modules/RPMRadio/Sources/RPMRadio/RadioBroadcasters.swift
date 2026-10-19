import Foundation

/// The broadcasters known to carry advertising, matched by their website and by their name.
///
/// Ported from `RPM.Core/Radio/RadioBroadcasters.cs`, with the same tests. Change both, or the
/// phone and the desktop app will mark different stations.
///
/// The directory has no field for advertising, and its tags rarely say so. Of 400 Dutch stations,
/// two carry a tag that ``RadioAds`` can read. So the broadcasters are listed here. Every entry is
/// a public broadcaster that is partly funded by advertising, or a commercial group. A station not
/// on the list is not marked. A short list therefore means a missing mark, never a false one.
///
/// The website is matched first, because a domain belongs to one organisation. Names such as
/// "Joe" and "538" are ordinary words. The name is the fallback for stations with no homepage. It
/// is matched on whole words from the start, so "NPO" does not match "Nippon".
public enum RadioBroadcasters {
    /// Whether this station belongs to a broadcaster known to carry advertising.
    public static func carriesAds(name: String?, homepage: String?) -> Bool {
        knownSite(homepage) || knownName(name)
    }

    /// Whether the station's site is one of the sites in the list, or a subdomain of one. So
    /// radio1.nl, www.nporadio1.nl and nporadio1.nl all match.
    private static func knownSite(_ homepage: String?) -> Bool {
        guard let homepage, let page = URL(string: homepage), page.scheme != nil,
              let host = page.host?.lowercased(), !host.isEmpty
        else { return false }

        return sites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Whether the station's name starts with one of the names in the list, as whole words:
    /// "NPO Radio 2", "BBC Radio 6 Music".
    private static func knownName(_ name: String?) -> Bool {
        let folded = fold(name ?? "")
        guard !folded.isEmpty else { return false }

        return names.contains { folded == $0 || folded.hasPrefix($0 + " ") }
    }

    /// Lower case. Each run of characters that are not letters or digits becomes one space. So
    /// "Q-music" becomes "q music", which matches the entry "q music" in the list.
    private static func fold(_ text: String) -> String {
        var folded = ""
        for c in text {
            if c.isLetter || c.isNumber {
                folded += c.lowercased()
            } else if let last = folded.last, last != " " {
                folded.append(" ")
            }
        }
        while folded.last == " " { folded.removeLast() }
        return folded
    }

    /// The websites, registrable domain only. Public broadcasters and commercial groups are both
    /// listed. The mark is about what the listener hears.
    private static let sites: [String] = [
        // Netherlands: public broadcasters (NPO, which carries STER advertising) and the commercial
        // groups
        "npo.nl", "nporadio1.nl", "nporadio2.nl", "npo3fm.nl", "nporadio4.nl", "nporadio5.nl",
        "radio1.nl", "radio2.nl", "3fm.nl", "radio4.nl", "radio5.nl", "omroep.nl", "funx.nl",
        "538.nl", "radio538.nl", "skyradio.nl", "radio10.nl", "radioveronica.nl", "talpanetwork.com",
        "qmusic.nl", "joe.nl", "joe.be", "qmusic.be", "100p.nl", "slam.nl", "sublimefm.nl",
        "arrow.nl", "grootnieuwsradio.nl", "omroepgelderland.nl",
        // Belgium, Germany, France, Italy, Spain, UK, Ireland, Nordics, Austria, Switzerland
        "vrt.be", "rtbf.be", "radio1.be", "studiobrussel.be", "nostalgie.be",
        "ard.de", "wdr.de", "ndr.de", "swr.de", "br.de", "mdr.de", "rbb-online.de", "hr.de",
        "deutschlandfunk.de", "deutschlandradio.de", "1live.de", "antenne.de", "ffh.de", "radio.de",
        "radiofrance.fr", "franceinter.fr", "franceinfo.fr", "francemusique.fr", "fip.fr",
        "nrj.fr", "rtl.fr", "europe1.fr", "rmc.fr", "skyrock.com",
        "rai.it", "radiorai.it", "rtl.it", "radiodeejay.it", "radio105.net", "virginradio.it",
        "rtve.es", "cadenaser.com", "los40.com", "cope.es", "ondacero.es",
        "bbc.co.uk", "bbc.com", "global.com", "heart.co.uk", "capitalfm.com", "classicfm.com",
        "bauermedia.co.uk", "absoluteradio.co.uk", "talksport.com",
        "rte.ie", "todayfm.com",
        "sverigesradio.se", "nrk.no", "dr.dk", "yle.fi",
        "orf.at", "hitradio-oe3.at", "srf.ch", "rsi.ch", "rts.ch",
        // North America
        "npr.org", "wnyc.org", "iheart.com", "iheartmedia.com", "audacy.com", "cumulusmedia.com",
        "cbc.ca", "radio-canada.ca",
    ]

    /// The broadcaster names, for stations with no homepage. They are folded the same way as the
    /// station's name.
    private static let names: [String] = [
        "npo", "npo radio", "npo 3fm", "3fm", "radio 538", "538", "sky radio", "radio 10",
        "radio veronica", "veronica", "qmusic", "q music", "joe", "100 nl", "slam", "sublime",
        "arrow classic rock", "funx", "bnr", "kink",
        "vrt", "studio brussel", "rtbf", "mnm",
        "ard", "wdr", "ndr", "swr", "br", "mdr", "hr", "1live", "deutschlandfunk", "antenne bayern",
        "radio france", "france inter", "france info", "france musique", "france culture", "nrj",
        "europe 1", "rtl", "rmc", "skyrock",
        "rai", "radio deejay", "radio 105", "virgin radio",
        "rne", "cadena ser", "los 40", "cope", "onda cero",
        "bbc", "heart", "capital", "classic fm", "smooth", "absolute radio", "talksport", "lbc",
        "rte", "today fm",
        "sveriges radio", "nrk", "dr p", "yle",
        "orf", "hitradio o3", "srf", "rsi", "rts",
        "npr", "wnyc", "cbc", "ici radio canada",
    ]
}
