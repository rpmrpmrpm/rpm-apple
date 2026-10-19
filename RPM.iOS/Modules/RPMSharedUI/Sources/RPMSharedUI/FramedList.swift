import SwiftUI
import RPMDesign
import RPMLibrary
import RPMStages

/// A generated list as the cover squares draw it: its name and the colours of its frame.
///
/// **One source for every screen.** The playlists tab, the list's own page, the home rows and the
/// home banner all use this type, so a list never gets two different covers.
public struct FramedList: Equatable {
    /// The name shown in the frame's band, in the current locale.
    public let name: String

    public let look: GeneratedListLook.Look

    /// The frame for a list, or nil when the list has no frame: a playlist made by the user, a
    /// folder, the queue, the marked songs, and a generated list whose kind this build has no
    /// colours for (an older app reading data from a newer desktop app).
    ///
    /// Also nil when the frame drawing is missing from the bundle, so the square keeps its own
    /// picture instead of showing an empty frame.
    public static func of(_ set: PlaylistSet?) -> FramedList? {
        guard PlaylistFrame.has,
              let set, set.origin == .generated, let cut = set.cut,
              let look = GeneratedListLook.of(kind: cut.kind, genre: cut.genre, decade: cut.decade)
        else { return nil }

        return FramedList(name: set.name, look: look)
    }

    /// The room for this list, fixed on one palette (no transition).
    ///
    /// The frame has three colours, passed in the order the room needs them: the middle one is
    /// most of what is seen, the hot one is the light, and the deep one is the shadow. The tree
    /// square, the header of the list's own page and the home card therefore show the same room.
    public var room: RoomDissolve {
        let settled = RoomPalette.from(tint: floats(look.trio.mid),
                                       glow: floats(look.trio.hot),
                                       shade: floats(look.trio.deep))

        return RoomDissolve(from: settled, to: settled, at: 0)
    }

    private func floats(_ colour: RGB) -> SIMD3<Float> {
        SIMD3(Float(colour.r) / 255, Float(colour.g) / 255, Float(colour.b) / 255)
    }
}

extension View {
    /// Draws the frame over this view, when the list has one.
    ///
    /// **Overlaid, not merged into the picture.** The desktop app has to store a JPEG. Here the
    /// frame is a second layer, so the room behind its window stays live on a card that animates it.
    @ViewBuilder
    public func listFrame(_ framed: FramedList?, edge: CGFloat) -> some View {
        if let framed, let drawing = PlaylistFrame.image(name: framed.name,
                                                         look: framed.look, edge: edge) {
            overlay {
                Image(uiImage: drawing)
                    .resizable()
                    .frame(width: edge, height: edge)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}
