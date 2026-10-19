import Foundation

/// How the admin changed the way one station is shown (rpm.Admin's station edit page, published in
/// `radio/state`): its title, its tags, the line on its banner card. Each value is nil where the
/// station's own is used. `tags` replace the directory's for genres only; the ads rule reads the
/// directory's own. The desktop's `StationEdit` and the Android `StationEdit`.
public struct StationEdit: Equatable, Hashable, Sendable {
    public let name: String?
    public let tags: [String]?
    public let description: String?

    public init(name: String?, tags: [String]?, description: String?) {
        self.name = name
        self.tags = tags
        self.description = description
    }

    /// The edit with blank values as nil and tags read as the directory's are (trimmed, lower case,
    /// each once), or nil where nothing is left of it.
    public static func of(name: String?, tags: [String]?, description: String?) -> StationEdit? {
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let tagged = tags?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let line = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let edit = StationEdit(name: title?.isEmpty == false ? title : nil,
                               tags: tagged?.isEmpty == false ? tagged : nil,
                               description: line?.isEmpty == false ? line : nil)
        return edit.name == nil && edit.tags == nil && edit.description == nil ? nil : edit
    }
}

/// What the rpm API says about stations: the ones the admin hid, and the ones shown with a different
/// title, tags or description, by lower-case uuid. The Android `StationRules`. Applied when a list is
/// drawn, never when an answer is stored: the rules can land after the answer.
public struct StationRules: Equatable, Sendable {
    /// Lower-case uuids.
    public let hidden: Set<String>
    /// By lower-case uuid.
    public let edits: [String: StationEdit]

    public init(hidden: Set<String>, edits: [String: StationEdit]) {
        self.hidden = hidden
        self.edits = edits
    }

    /// Nothing hidden and nothing edited: the app before the first answer.
    public static let none = StationRules(hidden: [], edits: [:])

    /// Hidden only when the station and every entry folded into it are hidden, as on the desktop.
    public func hides(_ station: RadioStation) -> Bool {
        guard !hidden.isEmpty else { return false }
        return hidden.contains(station.uuid.lowercased())
            && station.alsoFiledAs.allSatisfy { hidden.contains($0.lowercased()) }
    }

    /// The admin's edit for `station`: its own entry's, else the first folded entry's that has one
    /// (the admin saves an edit under every entry of a station, so the folded entries are the fallback
    /// for a fold the admin's index grouped differently).
    public func edit(of station: RadioStation) -> StationEdit? {
        guard !edits.isEmpty else { return nil }
        if let own = edits[station.uuid.lowercased()] { return own }
        return station.alsoFiledAs.lazy.compactMap { self.edits[$0.lowercased()] }.first
    }

    /// `station` carrying its edit as the rules stand now, in place of any edit it already carried.
    public func edited(_ station: RadioStation) -> RadioStation {
        let edit = edit(of: station)
        guard edit != station.edit else { return station }
        var drawn = station
        drawn.edit = edit
        return drawn
    }

    /// `stations` without the hidden ones, carrying their edits, with the full name given where two
    /// would print the same.
    public func shown(_ stations: [RadioStation]) -> [RadioStation] {
        RadioNames.distinguish(stations.filter { !hides($0) }.map(edited))
    }

    /// The uuids of the stations the admin filed under `genre` by their tags, in a stable order. A
    /// genre search adds them to the directory's answer, which is asked by the directory's own tags and
    /// never returns them (``RadioResults/withRetagged(_:_:_:)``).
    public func retagged(into genre: String) -> [String] {
        edits.filter { _, edit in
            guard let tags = edit.tags else { return false }
            return RadioGenres.is(RadioNames.genres(tags), genre)
        }
        .keys.sorted()
    }
}
