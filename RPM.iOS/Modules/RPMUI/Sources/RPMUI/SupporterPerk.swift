import SwiftUI

/// One thing supporters get: its words and its glyph. The desktop (`SupporterPerks.All`), the
/// Android TV set-up and the Android phone list the same eight, in the same order.
public struct SupporterPerk: Sendable {
    /// The string key of the words.
    public let key: String
    public let glyph: String

    /// Drawn in gold: the two perks that other people can see, the backdrop and the mark. The rest
    /// are drawn in the app's cyan.
    public let gold: Bool

    /// All of them, storage first and the community last.
    public static let all: [SupporterPerk] = [
        SupporterPerk(key: "Supporter_PerkStorage", glyph: Glyph.cloud, gold: false),
        SupporterPerk(key: "Supporter_PerkBitrate", glyph: Glyph.waveform, gold: false),
        SupporterPerk(key: "Supporter_PerkRecognition", glyph: Glyph.fingerprint, gold: false),
        SupporterPerk(key: "Supporter_PerkDj", glyph: Glyph.sliders, gold: false),
        SupporterPerk(key: "Supporter_PerkKaraoke", glyph: Glyph.microphone, gold: false),
        SupporterPerk(key: "Supporter_PerkBackdrop", glyph: Glyph.palette, gold: true),
        SupporterPerk(key: "Supporter_PerkBadge", glyph: Glyph.heart, gold: true),
        SupporterPerk(key: "Supporter_PerkCommunity", glyph: Glyph.people, gold: false),
    ]
}
