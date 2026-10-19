import SwiftUI

/// One sleeve in a square slot: filled, and **cut from the FOOT**.
///
/// A rectangular cover in a square tile has to lose something. The framework's own answer is to
/// cut it off both ends (a centred fill). That is the wrong end to cut from, twice over: the top
/// of a sleeve carries the record's name and the artist's, and the top of a photographed cover
/// carries a face. A wall of covers with their titles cut off the top and their chins cut off
/// the bottom looks like a wall of mistakes.
///
/// So the top is always kept, and whatever does not fit is cut from the bottom.
///
/// **`Color.clear` and an overlay, and not the image itself**, because a resizable image that
/// fills its frame reports the SCALED size as its own. In the page's ground, a square sleeve
/// over a tall page made the whole view eight hundred points wide. With an overlay, the slot is
/// the slot and the picture is drawn into it.
struct Sleeve: View {
    let image: Image

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}
