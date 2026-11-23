import Foundation

/// The stations with a card picture: a 16:9 picture the admin chose for the station's card
/// (rpm.Admin's station edit page). `radio/state` lists them under every row of the station, and the
/// API serves each at `radio/card/{uuid}`. The desktop's `RadioState.CardAddress` and the Android
/// `StationCards`.
public struct StationCards: Equatable, Sendable {
    /// Lower-case uuids.
    public let stations: Set<String>

    /// Changes whenever a picture changes. It goes on the picture's address, so a changed picture is
    /// a new address. Empty where no picture was ever set.
    public let stamp: String

    public init(stations: Set<String>, stamp: String) {
        self.stations = stations
        self.stamp = stamp
    }

    /// No pictures: the app before the first answer, and an API that lists none.
    public static let none = StationCards(stations: [], stamp: "")

    /// The uuid to ask for `station`'s picture under: its own entry's, else the first folded entry's
    /// that has one, as edits are looked up (``StationRules/edit(of:)``). Nil where it has none.
    public func uuid(of station: RadioStation) -> String? {
        guard !stations.isEmpty else { return nil }
        return ([station.uuid] + station.alsoFiledAs).lazy
            .map { $0.lowercased() }
            .first { stations.contains($0) }
    }

    /// Whether `station` has a card picture.
    public func has(_ station: RadioStation) -> Bool { uuid(of: station) != nil }
}
