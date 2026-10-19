import Foundation

/// A station's name with the stream's specification taken out.
///
/// Ported from `RPM.Core/Radio/RadioNames.cs`.
///
/// **What taggers put in the name field.** Examples: "PureClassixx #Flac", "Intense Radio - We love
/// Dance #HQ# FLAC", "Smooth FM 91.5 - Melbourne - 91.5 FM (AAC+ 320k)". None of that is what the
/// station is called. It is the codec and the bitrate, written into the name. The directory's own
/// codec and bitrate fields are not what a search matches on, so taggers put them in the name
/// instead. The app already prints those two fields on the line underneath every row.
///
/// **Only what is clearly a specification is removed.** A station is called Radio 538, or 100% NL,
/// or Studio Brussel. Numbers and punctuation in a name are usually part of the name. So a run is
/// removed only when it is a KNOWN quality word. Everything else is left exactly as the broadcaster
/// wrote it. Getting this wrong in the other direction renames a station, which is worse than an
/// untidy line.
public enum RadioNames {
    /// The name as it should be shown. It returns the original when there is nothing to remove. It
    /// **never returns an empty string**. A name that is entirely specification keeps it, because a
    /// blank row is worse than an untidy one.
    public static func clean(_ name: String?) -> String {
        strip(headline(name ?? ""), original: name)
    }

    /// The same, with the strapline kept: "Concertzender - Hard Bop" rather than "Concertzender".
    /// This is for stations that need the strapline to be told apart.
    public static func full(_ name: String?) -> String {
        strip(name ?? "", original: name)
    }

    /// A list of stations, with straplines added back to the ones that need them.
    ///
    /// A strapline is noise until two stations share a head. Then it is the only thing that tells
    /// them apart. Concertzender broadcasts "De Gehoorde Stilte" and "Hard Bop" as separate
    /// stations. A list that shows "Concertzender" twice looks broken. **A station cannot know this
    /// about itself.** It is a fact about the LIST. So it is worked out here, once, where the whole
    /// list is available.
    public static func distinguish(_ stations: [RadioStation]) -> [RadioStation] {
        guard stations.count >= 2 else { return stations }

        // A station with a title the admin set counts under that title, and is never given a
        // strapline.
        var heads: [String: Int] = [:]
        for station in stations {
            heads[(station.edit?.name ?? clean(station.name)).lowercased(), default: 0] += 1
        }

        // Nothing shares a head. This is the usual list.
        guard heads.values.contains(where: { $0 > 1 }) else { return stations }

        return stations.map { station in
            if station.edit?.name != nil { return station }
            let head = clean(station.name)
            let whole = full(station.name)

            guard heads[head.lowercased(), default: 0] > 1, head != whole else { return station }

            var told = station
            told.shownName = whole
            return told
        }
    }

    /// The tags worth printing: those that say what a station PLAYS. Not those that say how it is
    /// served, or how the directory files it.
    ///
    /// A tag that starts with "#" is directory housekeeping. "##browserfriendly" is a note about
    /// the stream's URL. A tag made only of specification is the codec and bitrate written a second
    /// time.
    public static func genres(_ tags: [String]?) -> [String] {
        guard let tags, !tags.isEmpty else { return [] }

        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.first != "#", !allQuality(trimmed) else { return nil }
            return trimmed
        }
    }

    // ── the cutting ──

    private static func strip(_ text: String, original: String?) -> String {
        guard !text.isEmpty else { return original ?? "" }

        let chars = Array(text)
        var cut = ""
        var at = 0

        while at < chars.count {
            if let end = marker(chars, at) {
                at = end   // A specification: dropped.
                continue
            }
            cut.append(chars[at])
            at += 1
        }

        let left = tidy(cut)
        return left.isEmpty ? text : left
    }

    /// The station's name up to its first subtitle. Everything after a spaced dash is a strapline,
    /// and a row is not the place to show a strapline.
    ///
    /// **Spaced dashes only. That is the whole rule.** A hyphen inside a word is part of the word:
    /// Hi-Fi Radio, K-Rock, Radio X-tra, Rock-FM. Cutting at any dash would rename every one of
    /// these. A renamed station is worse than a station with a strapline.
    private static func headline(_ name: String) -> String {
        var at: String.Index?

        for dash in dashes {
            guard let found = name.range(of: dash), found.lowerBound != name.startIndex else { continue }
            if at == nil || found.lowerBound < at! { at = found.lowerBound }
        }

        // A name that opens with one has no head to keep, so it keeps all of itself.
        guard let at else { return name }
        return String(name[name.startIndex..<at]).trimmingCharacters(in: .whitespaces)
    }

    /// What separates a name from its strapline. Always with a space on both sides.
    private static let dashes = [" - ", " \u{2013} ", " \u{2014} ", " -- ", " | "]

    /// Where the specification that starts at `at` ends, or nil if none starts there.
    private static func marker(_ text: [Character], _ at: Int) -> Int? {
        // "#HQ", "#HQ#", "#Flac": the hash form. A directory search box treats it as a keyword. A
        // reader sees it as noise.
        if text[at] == "#" {
            var end = at + 1
            while end < text.count, text[end].isLetter || text[end].isNumber || text[end] == "+" {
                end += 1
            }

            guard isQuality(String(text[(at + 1)..<end])) else { return nil }
            return end < text.count && text[end] == "#" ? end + 1 : end
        }

        // A bracketed group that is nothing but specification: "(AAC+ 320k)".
        let close: Character? = text[at] == "(" ? ")" : text[at] == "[" ? "]" : nil
        if let close {
            guard let shut = text[(at + 1)...].firstIndex(of: close),
                  allQuality(String(text[(at + 1)..<shut]))
            else { return nil }
            return shut + 1
        }

        // A bare run of specification, wherever it sits: "- MP3 128k", "| 320 kbps", "FLAC".
        guard text[at].isLetter || text[at].isNumber else { return nil }
        // A run cannot start in the middle of a word.
        if at > 0, text[at - 1].isLetter || text[at - 1].isNumber { return nil }

        var run = at
        var last = -1
        var named = false

        while run < text.count {
            var word = run
            while word < text.count, text[word].isLetter || text[word].isNumber || text[word] == "+" {
                word += 1
            }
            guard word != run else { break }

            let it = String(text[run..<word])
            if isQuality(it) {
                named = true
            } else if !isBitrate(it) {
                break   // A word that is neither a specification nor a bitrate ends the run.
            }

            last = word
            run = word
            while run < text.count, text[run] == " " || text[run] == "/" { run += 1 }
        }

        // A run of bare numbers is not a specification. "538 TOP 50" and "Kiss 108" are names. A
        // run needs a word that NAMES a specification.
        return named && last > at ? last : nil
    }

    /// Whether everything between a pair of brackets is specification, and at least one word says
    /// so by name.
    private static func allQuality(_ inside: String) -> Bool {
        var named = false

        for word in inside.split(whereSeparator: { " /,-".contains($0) }) {
            if isQuality(String(word)) {
                named = true
            } else if !isBitrate(String(word)) {
                return false
            }
        }

        return named
    }

    /// Whether one word NAMES part of a stream's specification: a codec, a rate with its unit on
    /// it, or one of the words that taggers write to say "this one sounds good".
    private static func isQuality(_ word: String) -> Bool {
        var folded = word.trimmingCharacters(in: .whitespaces).lowercased()
        while folded.hasSuffix("+") { folded.removeLast() }
        guard !folded.isEmpty else { return false }

        if words.contains(folded) { return true }

        // "128k", "320kbps", "1411k": a number with its unit on it.
        for unit in units where folded.hasSuffix(unit) {
            let rate = String(folded.dropLast(unit.count))
            if !rate.isEmpty, isBitrate(rate) { return true }
        }

        return false
    }

    /// Whether a word is a bare number in the range that a stream's bitrate falls in.
    ///
    /// **It is never enough on its own.** "538", "100" and "108" are all in that range, and all of
    /// them are station names. It counts only beside a word that names a specification. That is
    /// what makes "320 kbps" a bitrate, and "Kiss 108" a station. It accepts DIGITS only. "90s" is
    /// a decade. Trimming the "s" off to find a number is how a genre came to be read as a bitrate.
    private static func isBitrate(_ word: String) -> Bool {
        guard !word.isEmpty, word.allSatisfy({ $0.isASCII && $0.isNumber }),
              let rate = Int(word)
        else { return false }

        return rate >= slowest && rate <= fastest
    }

    /// The units written after a bitrate. Longest first, so "kbps" is not read as a bare "k" with
    /// "bps" left over.
    private static let units = ["kbps", "kbit", "kbs", "kb", "k"]

    /// Closes up what a removal leaves behind. That is the double space where a specification
    /// stood, and the dash or pipe that the tagger wrote in front of it.
    private static func tidy(_ text: String) -> String {
        var run = ""
        var space = false

        for c in text {
            if c.isWhitespace { space = true; continue }
            if space, !run.isEmpty { run.append(" ") }
            space = false
            run.append(c)
        }

        return run.trimmingCharacters(in: danglers)
    }

    /// What a name is left ending or starting with, once its specification has been removed.
    private static let danglers = CharacterSet(charactersIn: " -\u{2013}|,:/()[]")

    /// Codecs, and the words for "this stream is a good one".
    private static let words: Set<String> = [
        "mp3", "aac", "aacp", "aac+", "he-aac", "heaac", "ogg", "opus", "vorbis", "flac", "wma", "wav",
        "alac", "mp2", "m4a", "hls",
        "hq", "hd", "sq", "lq", "hifi", "hi-fi", "highquality", "lowquality", "lofi", "lo-fi",
        "kbps", "kbit", "kb", "bitrate", "stereo", "mono", "cd", "cdq", "quality",
    ]

    /// The range that a stream's bitrate falls in. Below it, a number is a frequency or part of a
    /// name. Above it, the same.
    private static let slowest = 8
    private static let fastest = 2000

    /// The name reduced to what identifies the station, not the entry. Specification is removed.
    /// Case, punctuation and accents are flattened. The words that say "this is a radio station"
    /// are dropped. The result is never shown anywhere. It exists to be compared.
    ///
    /// **Why the shown name is not enough.** Anybody may file a stream. So one station arrives
    /// under whatever each contributor typed. At one point the directory held "Qmusic", "Q-Music",
    /// "Q music Nederland" and "QMUSIC NEDERLAND". It also held "Heart", "Heart FM" and "Heart UK",
    /// and "ffn" and "radio ffn". "Radio Veronica" and "Radio Veronica Live" were there too. Each
    /// group is one station. Squashing the name alone does not join the spellings.
    ///
    /// **Word by word, and the words must then be equal.** Not a prefix. "Radio 10" and "Radio 10
    /// non-stop" are two channels, as are Qmusic and Qmusic Non-Stop. A prefix rule would delete
    /// the second of each pair. A word that is not noise is content, and content is what tells a
    /// broadcaster's channels apart.
    ///
    /// **A country word only after the first word.** At the head it is part of the brand. Examples:
    /// GB News, France Inter, Radio Kiss Kiss. Dropping it there once merged GB News into a station
    /// called News Radio UK. After the first word it is a qualifier: Qmusic Nederland, Classic FM
    /// UK, Virgin Radio Italia.
    ///
    /// **Never empty.** A name made only of these words keeps them. Otherwise a station with an
    /// empty name would be filed together with every other station with an empty name.
    ///
    /// - Parameter countryCode: the station's own ISO code. It decides whether a word is the
    ///   country's name.
    ///   Without it, no country word is removed.
    public static func fold(_ name: String?, _ countryCode: String?) -> String {
        // `parts`, not `words`. This type already has a static `words`, and a local with that name
        // would hide it.
        let parts = split(full(name))
        guard !parts.isEmpty else { return "" }

        let geo = geoWords[(countryCode ?? "").trimmingCharacters(in: .whitespaces).uppercased()]

        var kept: [String] = []
        for (i, part) in parts.enumerated() {
            if noiseWords.contains(part) { continue }
            if i > 0, let geo, geo.contains(part) { continue }
            kept.append(part)
        }

        // If nothing is left, the country words are put back first. If that still leaves nothing,
        // all the words are kept. A station called only "Radio", or only "Nederland", must still be
        // filed under something of its own.
        if kept.isEmpty { kept = parts.filter { !noiseWords.contains($0) } }
        return (kept.isEmpty ? parts : kept).joined()
    }

    /// The words of a name, in lower case, with accents off and punctuation removed.
    ///
    /// The split uses the same Unicode test as `NameMatch.squash`. A reader that only checks ASCII
    /// turns "Вести FM" and "Ретро FM" into the one word "fm". Two Russian stations would then be
    /// merged into one.
    private static func split(_ text: String) -> [String] {
        var parts: [String] = []
        var part = ""

        for c in deaccent(text) {
            if c.isLetter || c.isNumber || c == "+" {
                // append(contentsOf:) is used, not Character(c.lowercased()). Lowercasing one
                // character can yield two, and Character(_:) traps on a string that is not exactly
                // one grapheme.
                part.append(contentsOf: c.lowercased())
                continue
            }
            if !part.isEmpty { parts.append(part); part = "" }
        }

        if !part.isEmpty { parts.append(part) }
        return parts
    }

    /// The same text with its diacritics removed. So "Rádio Comercial" and "Radio Comercial"
    /// compare as the same words.
    private static func deaccent(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Words that say a thing is a radio station, or say how it sounds. They say nothing about
    /// which station it is.
    ///
    /// The codec and quality words are here as well as in ``words``. ``full(_:)`` removes only a
    /// run of them. For example, "QMUSIC NEDERLAND AAC HIGH" comes back as "QMUSIC NEDERLAND HIGH",
    /// because "HIGH" is not a codec, so it ends the run.
    private static let noiseWords: Set<String> = [
        "radio", "radios", "fm", "am", "hd", "sd", "dab", "live", "stream", "streaming",
        "online", "net", "web", "webradio", "digital", "channel", "station", "the", "and",
        "mp3", "aac", "aacp", "ogg", "opus", "vorbis", "flac", "wma", "hls", "high", "low",
        "hq", "sq", "lq", "hifi", "kbps", "kbit", "kb", "quality", "stereo", "official",
    ]

    /// The names that each country uses for itself in its station names, by ISO code.
    ///
    /// This is a list of facts, not a rule. Nothing can turn "NL" into "Nederland". A country that
    /// is not in the list keeps its qualifier. So if the list is short, the cost is a station
    /// listed twice. It never folds two stations into one.
    ///
    /// **No bare two-letter codes.** They are ordinary words in some languages. "de" is French.
    /// "in", "at" and "be" are English. "100% NL" is a station whose name is the "NL". The one
    /// exception is "uk". British stations label themselves with it, and it is worth having:
    /// Classic FM UK, LBC UK, Heart UK, Boom Radio UK, Gold Radio UK.
    private static let geoWords: [String: Set<String>] = [
        "NL": ["nederland", "nederlandse", "netherlands", "holland", "dutch"],
        "GB": ["uk", "britain", "british", "england", "unitedkingdom"],
        "US": ["usa", "america", "american"],
        "DE": ["deutschland", "germany", "german"],
        "FR": ["france", "french"],
        "IT": ["italia", "italy", "italian", "italiana"],
        "ES": ["espana", "spain", "spanish"],
        "BE": ["belgie", "belgium", "belgique"],
        "AT": ["osterreich", "austria"],
        "CH": ["schweiz", "switzerland", "suisse", "svizzera"],
        "SE": ["sverige", "sweden"],
        "NO": ["norge", "norway"],
        "DK": ["danmark", "denmark"],
        "FI": ["suomi", "finland"],
        "PT": ["portugal", "portuguesa"],
        "PL": ["polska", "poland"],
        "IE": ["ireland", "eire"],
        "CA": ["canada"],
        "AU": ["australia"],
        "BR": ["brasil", "brazil"],
        "MX": ["mexico"],
        "IN": ["india"],
    ]
}
