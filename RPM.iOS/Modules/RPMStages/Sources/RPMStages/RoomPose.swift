import Foundation

/// Where along its drift a room starts.
///
/// The room's figures are a function of its clock and nothing else. Rooms that start together, or
/// share one clock (such as the home banner's cards), would stand in the same pose and move in
/// lockstep. So each room starts a distance along its drift that is picked from what it shows, as the
/// desktop's `CardRoom` poses each card from its colours and its list.
///
/// **Picked from a name, not at random**, so two views of one card (the banner's copy of its first
/// card, which hands over to the card itself) draw the same frame, and a room that is scrolled away
/// and back starts from the pose it had.
public enum RoomPose {
    /// How far along a room can start, in the room's own seconds. It is long enough that names land
    /// far apart, and short enough that the shader's 32-bit clock still steps finely there (two
    /// thousandths of a second at the card's quickened 22,000).
    public static let span: Double = 10_000

    /// How far along the room named `seed` starts, from 0 up to ``span``. FNV-1a over the name's
    /// UTF-8: the same on every launch and every device, which Swift's own `hashValue` is not.
    public static func offset(of seed: String) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Double(hash % 10_000_000) / 10_000_000 * span
    }
}
