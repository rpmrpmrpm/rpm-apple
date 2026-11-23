import Foundation

/// What the home screen widget shows: the song that plays (or played last), whether it plays,
/// and the words read out for its keys.
///
/// The app writes it into the App Group folder (``WidgetShelf``), with the cover and a blurred
/// copy of the cover beside it, and the widget reads it from there. This file is built into both
/// the app and the widget extension.
struct WidgetCard: Codable, Equatable, Sendable {
    var title: String
    var artist: String
    var playing: Bool

    /// The accessible names of the three keys, in the app's language. The widget has no strings
    /// table of its own, so the app writes them from its own table.
    var previous: String
    var playPause: String
    var next: String

    /// The widget's kind. The app names it when it asks for the widget to be drawn again.
    static let kind = "NowPlaying"
}

/// The App Group folder that the app and the widget share, and the files in it.
enum WidgetShelf {
    /// The App Group's id, from the `RPMAppGroup` key of the running bundle's Info.plist, which is
    /// `RPM_APP_GROUP` in Signing.xcconfig.
    static var group: String? {
        Bundle.main.object(forInfoDictionaryKey: "RPMAppGroup") as? String
    }

    /// The widget's folder in the shared container. Nil when the build has no App Group, as an
    /// unsigned build has none.
    static var folder: URL? {
        guard let group, !group.isEmpty,
              let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return shared.appendingPathComponent("Widget", isDirectory: true)
    }

    static var cardFile: URL? { folder?.appendingPathComponent("card.json") }

    /// The cover, at most 600 pixels on its longer side.
    static var coverFile: URL? { folder?.appendingPathComponent("cover.jpg") }

    /// The cover, blurred, for the widget's background.
    static var backdropFile: URL? { folder?.appendingPathComponent("backdrop.jpg") }

    /// The card the app wrote last. Nil before the app has played anything.
    static func readCard() -> WidgetCard? {
        guard let file = cardFile, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetCard.self, from: data)
    }
}
