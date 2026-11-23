import AppIntents

/// What a key on the home screen widget asks of the player.
enum WidgetKey: Sendable {
    case previous
    case playPause
    case next
}

/// Where the widget's keys reach the player.
///
/// The keys are ``AudioPlaybackIntent``s. iOS runs those in the app's process, and starts the app
/// in the background first when it is not running. The app sets ``handle`` as its model is made
/// (`AppModel`), which happens on every launch, also in the background. In the widget's own
/// process ``handle`` stays nil and a key does nothing.
///
/// This file is built into both the app and the widget extension.
@MainActor
enum WidgetKeys {
    static var handle: ((WidgetKey) async -> Void)?

    static func press(_ key: WidgetKey) async {
        await handle?(key)
    }
}

// The titles below are required by `AppIntent`. They are not shown: the intents are not
// discoverable, so they appear in no list of shortcuts, and the widget names its keys with the
// app's own words (`WidgetCard`).

/// The widget's previous key.
struct WidgetPreviousIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WidgetKeys.press(.previous)
        return .result()
    }
}

/// The widget's play and pause key.
struct WidgetPlayPauseIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or pause"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WidgetKeys.press(.playPause)
        return .result()
    }
}

/// The widget's next key.
struct WidgetNextIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WidgetKeys.press(.next)
        return .result()
    }
}
