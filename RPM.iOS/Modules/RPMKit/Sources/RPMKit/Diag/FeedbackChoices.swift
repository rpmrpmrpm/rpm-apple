import Foundation

/// The kinds and areas the Send feedback window offers, with their string keys. The values are the
/// desktop's (`FeedbackKind`, `FeedbackArea` in rpm-desktop), because the admin site groups reports
/// by them and the server does not check them.
public enum FeedbackChoices {
    public struct Choice: Sendable, Equatable, Identifiable {
        public let value: String
        public let key: String
        public var id: String { value }

        init(_ value: String, _ key: String) {
            self.value = value
            self.key = key
        }
    }

    /// A problem first: it is the one that can be costing somebody their afternoon.
    public static let kinds = [
        Choice("problem", "Feedback_KindProblem"),
        Choice("idea", "Feedback_KindIdea"),
    ]

    /// The text box's placeholder for a kind.
    public static func placeholderKey(kind: String) -> String {
        kind == "idea" ? "Feedback_PlaceholderIdea" : "Feedback_PlaceholderProblem"
    }

    /// "Other" first, so someone who does not know which part a thing belongs to need not guess.
    public static let phoneAreas = [
        Choice("other", "Feedback_AreaOther"),
        Choice("playback", "Feedback_AreaPlayback"),
        Choice("library", "Feedback_AreaLibrary"),
        Choice("downloads", "Feedback_AreaDownloads"),
        Choice("cloud", "Feedback_AreaCloud"),
        Choice("radio", "Feedback_AreaRadio"),
        Choice("casting", "Feedback_AreaCasting"),
        Choice("interface", "Feedback_AreaInterface"),
    ]

    public static let tvAreas = [
        Choice("other", "Feedback_AreaOther"),
        Choice("playback", "Feedback_AreaPlayback"),
        Choice("library", "Feedback_AreaLibrary"),
        Choice("radio", "Feedback_AreaRadio"),
        Choice("interface", "Feedback_AreaInterface"),
    ]
}

/// The size a screenshot is drawn at before it is sent: the long edge at most `maxEdge` pixels,
/// never larger than the screen. The server takes at most 1,500,000 bytes of PNG.
public enum ShotFit {
    public static let maxEdge = 1600.0
    public static let maxBytes = 1_500_000

    /// The scale that brings a `width` by `height` picture down to `maxEdge`, or 1.
    public static func scale(width: Double, height: Double, maxEdge: Double) -> Double {
        let long = max(width, height)
        guard long > maxEdge, long > 0 else { return 1 }
        return maxEdge / long
    }
}
