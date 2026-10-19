import SwiftUI
import RPMKit

/// A sheet where the user writes a star rating and a text review for an album.
///
/// Port of the review sheet in `RPM.Mobile/Presentation/AlbumPage.xaml`. The star
/// rating is repeated here, as well as on the album page. A user who opens the sheet to
/// write text may not have rated the album yet, and Save must not depend on a control
/// on the screen behind the sheet.
public struct WriteReviewSheet: View {
    private let album: String
    private let onSave: (Double, String) async -> String?
    private let onDelete: (() async -> String?)?
    private let onClose: () -> Void

    /// - Parameter onDelete: `nil` when there is no review to delete. The Delete
    ///   button is then hidden, not disabled.
    public init(album: String, stars: Double, words: String,
                onSave: @escaping (Double, String) async -> String?,
                onDelete: (() async -> String?)? = nil,
                onClose: @escaping () -> Void) {
        self.album = album
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        _stars = State(initialValue: stars)
        _words = State(initialValue: words)
    }

    @State private var stars: Double
    @State private var words: String
    @State private var busy = false
    @State private var said: String?
    @FocusState private var typing: Bool

    public var body: some View {
        ZStack {
            Color.black.opacity(0xB3 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.get("Album_ReviewHeading"))
                        .font(RPMFont.displayBold(19))
                        .foregroundStyle(.white)

                    Text(album).rpmKicker().lineLimit(1)
                }

                StarRating(stars, size: 26) { stars = $0 }
                    .frame(maxWidth: .infinity, alignment: .center)

                TextEditor(text: $words)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(height: 130)
                    .padding(8)
                    .background {
                        let well = RoundedRectangle(cornerRadius: 10, style: .continuous)
                        well.fill(Color.black.opacity(0x22 / 255))
                            .overlay { well.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
                    }
                    .overlay(alignment: .topLeading) {
                        // `TextEditor` has no placeholder of its own, so one is drawn
                        // over it while the text is empty.
                        if words.isEmpty {
                            Text(Loc.get("Rpm_Album_ReviewPlaceholder"))
                                .font(RPMFont.display(15))
                                .foregroundStyle(RPMInk.white(0x66 / 255))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($typing)

                if let said {
                    Text(said)
                        .font(RPMFont.display(12))
                        .foregroundStyle(Color(red: 1, green: 0xB4 / 255, blue: 0xA0 / 255))
                }

                HStack(spacing: 10) {
                    Button(Loc.get("Cloud_Cancel"), action: onClose)
                        .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))

                    Button(action: save) {
                        if busy {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text(Loc.get("ArtPlace_Save"))
                        }
                    }
                    .buttonStyle(RPMGlassButton(.primary, radius: 10, height: 42, size: 14))
                    .disabled(busy)
                }

                if let onDelete {
                    Button(Loc.get("Album_DeleteReview")) {
                        busy = true
                        Task {
                            said = await onDelete()
                            busy = false
                            if said == nil { onClose() }
                        }
                    }
                    .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 38, size: 13))
                    .foregroundStyle(RPMInk.red)
                }
            }
            .padding(18)
            .frame(width: 330)
            .rpmGlassCard(radius: 18)
        }
    }

    private func save() {
        guard !busy else { return }

        busy = true
        said = nil
        typing = false

        Task {
            let trouble = await onSave(stars, words)
            busy = false

            guard let trouble else { onClose(); return }
            said = trouble
        }
    }
}
