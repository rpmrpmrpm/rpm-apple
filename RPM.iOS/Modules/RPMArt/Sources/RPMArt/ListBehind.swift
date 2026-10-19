import RPMDesign
import RPMLibrary

/// What goes behind a generated list's frame, best first. The room is used for the five lists that have no
/// artwork of their own. Next is the photograph shipped with the list. Last is the picture the cloud store
/// holds for it. The desktop uses this order too (`GeneratedCover`). The phone's order is in `PlaylistSleeve`,
/// then `CloudCovers.picture(of:edge:)`.
///
/// **The room comes before the stored picture.** This order matters. For those five lists, the stored picture
/// is the older drawn figure (metaballs), and the iOS app does not show it.
///
/// The view decides whether the room can be drawn. The frame must be in the bundle, and the device must
/// support the shader. A list that cannot show the room shows its stored picture.
public enum ListBehind: Equatable, Sendable {
    case room
    case photograph(GeneratedCut)
    case stored

    /// For a list cut from `cut`, or for a list somebody made (nil), which has only its stored picture.
    public static func of(_ cut: GeneratedCut?) -> ListBehind {
        guard let cut else { return .stored }
        if GeneratedListLook.of(kind: cut.kind, genre: cut.genre, decade: cut.decade)?.roomed == true {
            return .room
        }
        if PlaylistPhotos.has(cut) { return .photograph(cut) }
        return .stored
    }
}
