import Foundation
import Observation
import RPMKit
import RPMCast

/// The speakers on the network the player can play on, and the result of the last try. It is the
/// model of the speaker picker, and is the same on the phone and the TV.
///
/// Nothing is searched for until the picker is opened: browsing takes a few seconds and is not
/// needed before that.
@MainActor
@Observable
public final class Speakers {
    /// The speakers that answered the last search.
    public private(set) var found: [CastDevice] = []
    public private(set) var looking = false

    /// What went wrong with the last attempt, for the picker to show.
    public private(set) var trouble: String?

    private let player: Player

    public init(player: Player) {
        self.player = player
    }

    /// Searches for speakers for four seconds.
    public func look() async {
        looking = true
        found = await CastDiscovery().speakers(for: .seconds(4))
        looking = false
    }

    public func cast(to speaker: CastDevice) async {
        trouble = nil
        do { try await player.cast(to: speaker) }
        catch let refused as CastLink.Refused { trouble = Self.said(refused) }
        catch { trouble = Loc.get("Rpm_Cast_Unreachable", speaker.name) }
    }

    /// Moves the sound back to this device.
    public func stop() async {
        await player.stopCasting()
        trouble = nil
    }

    /// The message the picker shows for a speaker that refused.
    ///
    /// `NOT_ALLOWED` is the reason that needs its own message. **A speaker that is part of a
    /// stereo pair keeps advertising itself as before**, so it appears in the list and then
    /// refuses. The raw reason does not tell the user what to do. The pair (the group) is what
    /// can be cast to, and the message says that.
    nonisolated static func said(_ refused: CastLink.Refused) -> String {
        switch refused {
        case .launch(let reason, let speaker) where reason == "NOT_ALLOWED":
            return Loc.get("Cast_InPair", speaker)
        case .launch(_, let speaker):
            return Loc.get("Rpm_Cast_Refused", speaker)
        case .unreadable:
            return Loc.get("Rpm_Cast_Unreadable")
        }
    }
}
