import Foundation

/// The order the dial's stations are listed in.
///
/// ``listed`` is the order the directory returns, most played first. This is the order the page opens
/// on. The other cases sort the list in other ways, for when the listener does not know where a station
/// is in the list.
public enum StationOrdering: String, CaseIterable, Sendable {
    /// The directory's order, by how often each station is played.
    case listed
    case nameUp
    case nameDown

    /// Most votes first.
    case votes

    /// Highest bitrate first.
    case quality
}

/// Puts a list in the order asked for.
///
/// **Works on what is listed, as the sieve does.** It orders the page that the directory returned, and it
/// does not ask for another page. An A to Z of the dial covers only the stations in hand, not every
/// station in the directory.
///
/// **Every order is total.** Two stations with the same bitrate, or with no votes, would otherwise come
/// out in arrival order, and they could move while the listener scrolls. So each order ends with the name,
/// and the name ends with the id, which no two stations share. The same answer always gives the same list.
public enum StationSort {
    public static func by(_ order: StationOrdering,
                          _ stations: [RadioStation]) -> [RadioStation] {
        switch order {
        case .listed:
            return stations
        case .nameUp:
            return stations.sorted { byName($0, $1, up: true) }
        case .nameDown:
            return stations.sorted { byName($0, $1, up: false) }
        case .votes:
            return stations.sorted {
                $0.votes != $1.votes ? $0.votes > $1.votes : byName($0, $1, up: true)
            }
        case .quality:
            return stations.sorted {
                $0.bitrateKbps != $1.bitrateKbps
                    ? $0.bitrateKbps > $1.bitrateKbps
                    : byName($0, $1, up: true)
            }
        }
    }

    /// The text a station sorts by: the name as the row prints it, which is the cleaned name. Sorting by the
    /// raw name would file a station under a prefix such as "[HQ]".
    ///
    /// The comparison uses the current locale's rules, so names with accents sort where a reader of that
    /// language expects them. The id breaks ties. It is never shown, and it is compared as bytes, not as a
    /// name.
    private static func byName(_ a: RadioStation, _ b: RadioStation, up: Bool) -> Bool {
        let said = a.display.compare(b.display, options: .caseInsensitive,
                                     range: nil, locale: .current)
        guard said == .orderedSame else {
            return up ? said == .orderedAscending : said == .orderedDescending
        }
        return a.uuid < b.uuid
    }
}
