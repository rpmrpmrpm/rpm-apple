import Foundation

/// The kinds of station a dial is sorted by, and the tags that the directory's users give each
/// of them.
///
/// Ported from `RPM.Core/Radio/RadioGenres.cs`.
///
/// **Radio's own list, not the list for the record collection.** The app files ALBUMS under music
/// genres. A dial is different. A listener choosing a station picks Talk, News, Sports, Top 40,
/// Oldies or Adult Contemporary as readily as Jazz. A filter with only music genres would leave out
/// about a third of what is on the air.
///
/// **Twenty entries, because a menu is read, not searched.** Radio Browser has tens of thousands
/// of tags. Most of them are one station's spelling of another station's tag.
///
/// **The tags are matched, not shown.** Whoever adds a station writes its tags: "hiphop",
/// "hip hop", "rap", "urban". So every spelling worth knowing is listed against one label. The
/// label is the only thing a listener sees.
///
/// **The table was written from the directory, not from memory.** The entries are tags that Radio
/// Browser actually holds. They come from its own tag list and from the pages the pane lists,
/// biggest first. That is why the table has Spanish, German and Russian spellings. About a third
/// of the directory is not tagged in English.
public enum RadioGenres {
    /// The list in the order the menu offers it. The music comes first, roughly by how much of a
    /// dial it takes up. The three spoken formats come together at the end.
    public static let all: [String] = table.map(\.genre)

    /// The genres that are not music. The tuner's Music menu leaves them out.
    public static let notMusic: Set<String> = ["Talk", "News", "Sports"]

    /// The first of ``all`` that this tag names, or nil if it names none. A tag can name more than
    /// one genre. See ``names(_:)``.
    public static func match(_ tag: String?) -> String? {
        names(tag).first
    }

    /// Every one of ``all`` that this tag names, in the order they are written in it. Empty if it
    /// names none.
    ///
    /// **The whole tag is tried first.** "Classic rock" is a format of its own, and it contains the
    /// word "rock". So a tag that matches whole is answered whole, and is never split. The same
    /// trap is in "dance" inside "dancehall", and "jazz" inside "jazz funk".
    public static func names(_ tag: String?) -> [String] {
        guard let tag, !tag.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let folded = fold(tag)
        guard !folded.isEmpty else { return [] }

        if let genre = whole(folded) { return [genre] }

        return inWords(tag)
    }

    /// The tag to ask the DIRECTORY for when this genre is picked. It is nil if the genre is not in
    /// ``all``.
    ///
    /// The directory is asked for a term that its own tags contain, not for a whole tag. So one
    /// term reaches spellings that a listener would not think to try. "hop" finds "hiphop", "hip
    /// hop" and "hip-hop". "sport" finds "sports" and "sportstalk". Each result is still checked
    /// with ``is(_:_:)``. That check removes the reggaeton stations that "reggae" brings in from
    /// the Reggae page.
    public static func term(_ genre: String?) -> String? {
        table.first { $0.genre == genre }?.term
    }

    /// Whether any of these tags says the station is that kind of station.
    public static func `is`(_ tags: [String]?, _ genre: String) -> Bool {
        (tags ?? []).contains { names($0).contains(genre) }
    }

    /// The genres named by the WORDS of a tag that did not match whole. Examples: "club dance
    /// electronic house trance", "local news", "música pop", "rap hiphop rnb". Several genres
    /// written into one field are the second most common kind of tag in the directory, after a
    /// single word. A rule that read only whole tags left every one of those stations with no
    /// genre.
    ///
    /// The words are read from left to right. The longest run of words is tried first. So a run
    /// that is a format of its own is taken as that format, not as its parts. This runs only after
    /// the whole tag has failed. So nothing here can take a tag away from the label that matched it
    /// whole.
    private static func inWords(_ tag: String) -> [String] {
        let parts = words(tag)
        guard parts.count > 1 else { return [] }

        var named: [String] = []
        var at = 0

        while at < parts.count {
            var run = ""
            var hit: String?
            var end = at + 1

            for upto in at..<parts.count {
                run += parts[upto]
                if let genre = whole(run) {
                    hit = genre
                    end = upto + 1
                }
            }

            if let hit {
                if !named.contains(hit) { named.append(hit) }
                at = end
            } else {
                at += 1
            }
        }

        return named
    }

    /// The genre that a folded tag is, when taken whole, or nil.
    private static func whole(_ folded: String) -> String? {
        if let genre = byTag[folded] { return genre }

        // "Pop music", "Jazz radio", "Rock FM": the same tag with a common noun added at the end.
        // Many stations write it this way, and it means the same thing.
        for suffix in suffixes where folded.count > suffix.count && folded.hasSuffix(suffix) {
            if let genre = byTag[String(folded.dropLast(suffix.count))] { return genre }
        }

        return nil
    }

    /// A tag as it is compared: letters and digits only, in lower case, with accents removed. The
    /// directory holds "Hip-Hop", "hip hop" and "hiphop" for one kind of music. Only the
    /// punctuation differs. Accents are removed for the same reason: one station is tagged "música"
    /// by one person and "musica" by another.
    private static func fold(_ tag: String) -> String {
        String(bare(tag).filter { $0.isLetter || $0.isNumber })
    }

    /// A tag split into its words, each folded as ``fold(_:)`` folds it. Anything that is not a
    /// letter or a digit is a break. A tagger separates two genres with a space, a slash, a plus or
    /// an ampersand. Which one they used tells us nothing.
    private static func words(_ tag: String) -> [String] {
        bare(tag)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// The tag in lower case, with its accents removed. The fold and the word split both read this.
    private static func bare(_ tag: String) -> String {
        tag.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
    }

    /// The nouns that a station may add to the end of its own genre. This is read only after the
    /// whole tag has failed, so nothing here can take a tag away from a label that wanted it.
    private static let suffixes = ["music", "radio", "fm", "hits", "station"]

    /// Every spelling worth knowing, and the label each one means.
    ///
    /// This is one table, not a rule for each genre. The reason is that the data is not a pattern.
    /// It is what a large number of people typed into a form. The decades are under Oldies on
    /// purpose. A station that says it plays 70s or 80s is telling the listener when its music is
    /// from. That is the question Oldies answers.
    ///
    /// The entries are folded when they are read. So an entry can be written the way a tagger
    /// writes it ("hip-hop", "поп-музыка") rather than in folded form.
    ///
    /// The second column is the term sent to the DIRECTORY when the genre is picked. See
    /// ``term(_:)``. It is in the same row as the spellings on purpose. A genre with no search term
    /// would show whatever stations are already on screen. Keeping the term in this row means a
    /// genre cannot be added without one.
    private static let table: [(genre: String, term: String, tags: [String])] = [
        ("Pop", "pop", ["pop", "popular", "poprock", "europop", "kpop", "jpop", "cpop", "mandopop", "cantopop",
                 "synthpop", "teenpop", "electropop", "indiepop", "dreampop", "britpop", "popmusik",
                 "musicapop", "popmusica", "juvenil", "chanson", "chansonsfrancaises", "varietefrancaise",
                 "schlager", "volksmusik", "italianpop", "greekpop", "поп"]),
        ("Top 40", "top 40", ["top40", "top40s", "chr", "hits", "hitradio", "tophits", "charthits", "charts", "chart",
                    "contemporaryhitradio", "contemporaryhits", "contemporaryhitsradio", "currenthits",
                    "hitmusic", "toppop", "top10", "top20", "top50", "top100", "topcharts", "singlecharts",
                    "hitparade", "hitlist", "todayshits", "newhits", "musicaactual", "exitos"]),
        ("Adult Contemporary", "adult contemporary", ["adultcontemporary", "ac", "hotac", "softac", "adultcontempory",
                                "hotadultcontemporary", "softadultcontemporary", "easylistening", "easy",
                                "softrock", "soft", "adulthits", "adultstandards", "middleoftheroad", "mor",
                                "lovesongs", "ballads", "crooners", "beautifulmusic", "lightorchestral",
                                "strings", "instrumental", "newage", "relax", "relaxing", "relaxation",
                                "calm", "mellow", "unwind", "smooth"]),
        ("Oldies", "oldies", ["oldies", "goldenoldies", "classichits", "gold", "goldies", "nostalgia", "nostalgie",
                    "nostalgic", "retro", "vintage", "flashback", "decades", "ретро", "oldskool",
                    "oldschool", "classics", "clasicos", "musicadelrecuerdo", "recuerdo", "greatesthits",
                    "yesterday", "yesteryear", "50s", "60s", "70s", "80s", "90s", "00s", "1930", "1940",
                    "1950", "1960", "1970", "1980", "1990", "1950s", "1960s", "1970s", "1980s", "1990s",
                    "2000s", "50er", "60er", "70er", "80er", "90er", "2000er", "anni60", "anni70", "anni80",
                    "anni90", "annees60", "annees70", "annees80", "annees90", "fifties", "sixties",
                    "seventies", "eighties", "nineties"]),
        ("Rock", "rock", ["rock", "altrock", "alternative", "alternativerock", "adultalternative",
                  "adultalbumalternative", "indie", "indierock", "grunge", "punk", "punkrock", "postpunk",
                  "hardrock", "postrock", "garagerock", "rockpop", "progressiverock", "artrock",
                  "psychedelic", "psychedelicrock", "newwave", "рок", "gothic", "gothrock", "emo",
                  "modernrock", "southernrock", "folkrock", "rockalternativo", "rockmusik"]),
        ("Classic Rock", "classic rock", ["classicrock", "albumrock", "aor", "classicrockhits", "oldrock", "rockclassics",
                          "60srock", "70srock", "80srock", "rockandroll", "rocknroll"]),
        ("Metal", "metal", ["metal", "heavymetal", "deathmetal", "blackmetal", "thrash", "thrashmetal", "metalcore",
                   "deathcore", "grindcore", "powermetal", "numetal", "gothicmetal", "symphonicmetal",
                   "folkmetal", "speedmetal", "progressivemetal", "doom", "hardcore", "металл"]),
        ("Dance", "dance", ["dance", "edm", "club", "clubmusic", "clubbing", "clubdance", "dancefloor", "party",
                   "partymix", "houseparty", "disco", "italodisco", "nudisco", "discofox", "dancehits",
                   "eurodance", "danceclassics", "dancepop", "popdance", "rave", "mashup", "remix",
                   "remixes", "remixed", "djremix", "djmix", "djmixes", "djsets", "djset", "deejay",
                   "megamix", "hardstyle", "beachclub", "ibiza", "танцевальная"]),
        ("Electronic", "electronic", ["electronic", "electronica", "electro", "electronicdancemusic", "house",
                        "deephouse", "techhouse", "electrohouse", "progressivehouse", "soulfulhouse",
                        "tribalhouse", "futurehouse", "techno", "hypertechno", "hardtechno", "dubtechno",
                        "trance", "psytrance", "progressivepsytrance", "goa", "ambient", "chillout",
                        "chill", "lounge", "downtempo", "dubstep", "drumandbass", "drumbass", "dnb",
                        "dandb", "jungle", "neurofunk", "techstep", "breakbeat", "ukgarage", "ukfunky",
                        "minimal", "idm", "triphop", "synthwave", "retrowave", "vaporwave", "moombahton",
                        "industrial", "электронная", "чилаут"]),
        ("Hip-Hop", "hop", ["hiphop", "rap", "urban", "trap", "hiphoprap", "raphiphop", "oldschoolhiphop",
                     "gangsta", "grime", "drill", "boombap", "rapfrancais", "deutschrap", "рэп", "хип-хоп"]),
        ("R&B / Soul", "soul", ["rb", "rnb", "randb", "rhythmandblues", "soul", "funk", "funky", "funksoul",
                        "motown", "neosoul", "rbsoul", "rnbsoul", "soulfunk", "groove", "quietstorm",
                        "urbancontemporary", "blackmusic", "gospel"]),
        ("Jazz", "jazz", ["jazz", "smoothjazz", "softjazz", "contemporaryjazz", "classicjazz", "latinjazz", "bebop",
                  "swing", "bigband", "dixieland", "ragtime", "jazzfunk", "acidjazz", "fusion", "vocaljazz",
                  "nujazz", "pianojazz", "джаз"]),
        ("Blues", "blues", ["blues", "deltablues", "chicagoblues", "electricblues", "jumpblues", "soulblues",
                   "bluesrock", "rhythmblues"]),
        ("Country", "country", ["country", "americana", "bluegrass", "countryhits", "classiccountry", "hotcountry",
                     "todayscountry", "traditionalcountry", "countryclassics", "countrygold", "honkytonk",
                     "folk", "singersongwriter", "roots", "newcountry", "фолк"]),
        ("Classical", "classical", ["classical", "klassik", "klassisch", "klassiek", "klassieke", "clasica", "classique",
                       "musicaclasica", "opera", "operetta", "baroque", "symphonic", "symphony",
                       "orchestral", "choral", "chamber", "earlymusic", "romantic", "piano", "классическая"]),
        ("Latin", "latin", ["latin", "latino", "salsa", "reggaeton", "regueton", "bachata", "merengue", "cumbia",
                   "tango", "latinpop", "musicalatina", "musicalatinoamericana", "ranchera", "rancheras",
                   "banda", "bandanortena", "nortena", "nortenas", "norteno", "sierreno", "corrido",
                   "corridos", "grupera", "grupero", "vallenato", "tropical", "musicatropical",
                   "tropicalmusic", "balada", "baladas", "baladapop", "baladaromantica", "romantica",
                   "romanticas", "musicaromantica", "urbano", "musicaurbana", "mariachi", "bossanova",
                   "samba", "sertanejo", "mpb", "forro", "pagode", "musicamexicana", "mexicanmusic",
                   "mexicana", "musicaregional", "regionalmexicana", "regionalmexican",
                   "musicaregionalmexicana", "musicapopularmexicana", "musicatradicionalmexicana",
                   "traditionalmexicanmusic", "musicaenespanol", "popenespanol", "baladasenespanol",
                   "clasicosenespanol", "rockenespanol"]),
        ("Reggae", "reggae", ["reggae", "dancehall", "ska", "dub", "rootsreggae", "raggae", "ragga", "raggamuffin",
                    "loversrock"]),
        ("Talk", "talk", ["talk", "talkshow", "spokenword", "spoken", "chat", "discussion", "debate", "politics",
                  "politicaltalk", "conservativetalk", "podcast", "conversation", "interview",
                  "entrevistas", "comedy", "gesprek", "hablada", "radiohablada", "drama", "radiodrama",
                  "audiodrama", "oldtimeradio", "otr", "storytelling", "audiobooks", "hoerspiel",
                  "horspiel", "culture", "cultural", "cultura", "kultur", "education", "educational",
                  "educativa", "разговорное", "разговорный", "юмор"]),
        ("News", "news", ["news", "newstalk", "information", "currentaffairs", "headlines", "allnews", "actualites",
                  "actualite", "nachrichten", "noticias", "noticiero", "noticieros", "informativa",
                  "informativo", "informacion", "actualidad", "nieuws", "nyheter", "notizie", "journal",
                  "info", "weather", "wetter", "traffic", "verkehr", "npr", "новости", "информационное",
                  "информационный", "新闻"]),
        ("Sports", "sport", ["sport", "sports", "sportstalk", "sportnews", "football", "soccer", "futbol",
                    "basketball", "baseball", "hockey", "rugby", "cricket", "motorsport", "formula1",
                    "tennis", "golf", "esports", "deporte", "deportes", "deportivo", "deportiva", "voetbal"]),
    ]

    /// The table turned round. Every question starts from this direction: a station holds tags and
    /// asks what it is. It is built once. A page of stations has a hundred of these, and each one
    /// carries a dozen tags.
    private static let byTag: [String: String] = {
        var byTag: [String: String] = [:]

        for (genre, _, tags) in table {
            // The label itself, so a station tagged with the menu's own name is found without the
            // table having to repeat it.
            if byTag[fold(genre)] == nil { byTag[fold(genre)] = genre }
            for tag in tags where byTag[fold(tag)] == nil { byTag[fold(tag)] = genre }
        }

        return byTag
    }()
}
