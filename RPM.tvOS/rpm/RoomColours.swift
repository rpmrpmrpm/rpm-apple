import SwiftUI
import RPMArt
import RPMSharedUI
import RPMStages

/// The colours of an album cover as a settled room, for the small rooms behind cards.
enum RoomColours {
    static func of(_ colours: SleeveColours?) -> RoomDissolve {
        let settled = RoomPalette.from(tint: colours?.dominant?.asFloats,
                                       glow: colours?.highlight?.asFloats,
                                       shade: colours?.shade?.asFloats)
        return RoomDissolve(from: settled, to: settled, at: 0)
    }
}
