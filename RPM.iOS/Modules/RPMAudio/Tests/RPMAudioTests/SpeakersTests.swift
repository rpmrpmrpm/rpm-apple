import Testing
import Foundation
import RPMKit
import RPMCast
@testable import RPMAudio

/// What the speaker picker says when a speaker refuses. The same text is used on the phone
/// and on the TV.
struct SpeakersTests {
    /// A speaker in a stereo pair refuses with `NOT_ALLOWED`. The message tells the user to
    /// choose the group, and does not show the raw code.
    @Test func aPairedSpeakerIsToldToChooseTheGroup() {
        let said = Speakers.said(.launch(reason: "NOT_ALLOWED", speaker: "Keuken"))
        #expect(said == Loc.get("Cast_InPair", "Keuken"))
        #expect(!said.contains("NOT_ALLOWED"))
    }

    @Test func anyOtherRefusalSaysTheSpeakerDidNotAccept() {
        #expect(Speakers.said(.launch(reason: "LAUNCH_FAILED", speaker: "Woonkamer"))
                == Loc.get("Rpm_Cast_Refused", "Woonkamer"))
        #expect(Speakers.said(.unreadable) == Loc.get("Rpm_Cast_Unreadable"))
    }
}
