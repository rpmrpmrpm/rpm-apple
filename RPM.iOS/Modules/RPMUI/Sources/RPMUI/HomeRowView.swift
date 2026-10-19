import SwiftUI
import RPMKit
import RPMLibrary

/// One row of records, with a heading. It is used for the home screen's rows, the genre page's
/// rows, and Similar albums on the album page.
///
/// It is a horizontal scroll of the same tile that the wall draws, so there is only one way of
/// drawing a record to keep consistent.
public struct HomeRowView: View {
    private let heading: String
    private let albums: [CloudAlbum]
    private let covers: any CoverStore
    private let onOpen: (CloudAlbum) -> Void

    /// The edge length of a cover in a row. It is smaller than on the wall, so that part of the
    /// next cover is visible at the right-hand edge and shows that the row scrolls.
    static let art: Double = 132

    public init(heading: String, albums: [CloudAlbum], covers: any CoverStore,
                onOpen: @escaping (CloudAlbum) -> Void) {
        self.heading = heading
        self.albums = albums
        self.covers = covers
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(RPMFont.display(19))
                .padding(.horizontal, RPMLayout.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(albums) { album in
                        Button { onOpen(album) } label: {
                            AlbumTile(album: album, art: Self.art, covers: covers)
                                .frame(width: Self.art)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
            }
            // The row scrolls sideways inside a page that scrolls down. Clipping is disabled so
            // that the tiles are not cut off at the row's bounds.
            .scrollClipDisabled()
        }
    }
}
