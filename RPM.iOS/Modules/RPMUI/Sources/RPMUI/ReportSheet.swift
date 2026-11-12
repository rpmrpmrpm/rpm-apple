import SwiftUI
import RPMKit

/// A card over the page where the reader says why something should be looked at, and sends the
/// report. After a report is sent, the card says so and offers one key to close it.
///
/// It is drawn over the page like ``WriteReviewSheet``, and not as a system alert, so it has the
/// app's own look and a box with room for a few lines.
public struct ReportSheet: View {
    private let prompt: String
    private let onSend: (String) async -> String?
    private let onClose: () -> Void

    /// - Parameters:
    ///   - prompt: the sentence over the box: why a person reads the report.
    ///   - onSend: sends the report with the reader's note. Returns why it failed, or nil when it
    ///     was sent.
    public init(prompt: String, onSend: @escaping (String) async -> String?,
                onClose: @escaping () -> Void) {
        self.prompt = prompt
        self.onSend = onSend
        self.onClose = onClose
    }

    @State private var note = ""
    @State private var busy = false
    @State private var sent = false
    @State private var said: String?
    @FocusState private var typing: Bool

    /// The longest note the server takes, in characters.
    private static let longestNote = 2_000

    public var body: some View {
        ZStack {
            Color.black.opacity(0xB3 / 255)
                .ignoresSafeArea()
                .onTapGesture { if !busy { onClose() } }

            VStack(alignment: .leading, spacing: 14) {
                Text(Loc.get("Album_ReportTitle"))
                    .font(RPMFont.displayBold(19))
                    .foregroundStyle(.white)

                if sent {
                    Text(Loc.get("Album_ReportSent"))
                        .font(RPMFont.display(14))
                        .foregroundStyle(RPMInk.white(0xCC / 255))
                        .fixedSize(horizontal: false, vertical: true)

                    Button(Loc.get("Common_OK"), action: onClose)
                        .buttonStyle(RPMGlassButton(.primary, radius: 10, height: 42, size: 14))
                } else {
                    asking
                }
            }
            .padding(18)
            .frame(width: 330)
            .rpmGlassCard(radius: 18)
        }
    }

    @ViewBuilder
    private var asking: some View {
        Text(prompt)
            .font(RPMFont.display(13))
            .foregroundStyle(RPMInk.white(0xCC / 255))
            .fixedSize(horizontal: false, vertical: true)

        TextEditor(text: $note)
            .font(RPMFont.display(15))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .frame(height: 110)
            .padding(8)
            .background {
                let well = RoundedRectangle(cornerRadius: 10, style: .continuous)
                well.fill(Color.black.opacity(0x22 / 255))
                    .overlay { well.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
            }
            .overlay(alignment: .topLeading) {
                // `TextEditor` has no placeholder of its own, so one is drawn over it while the
                // text is empty.
                if note.isEmpty {
                    Text(Loc.get("Album_ReportPlaceholder"))
                        .font(RPMFont.display(15))
                        .foregroundStyle(RPMInk.white(0x66 / 255))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .focused($typing)
            .onChange(of: note) { _, typed in
                if typed.count > Self.longestNote { note = String(typed.prefix(Self.longestNote)) }
            }

        if let said {
            Text(said)
                .font(RPMFont.display(12))
                .foregroundStyle(Color(red: 1, green: 0xB4 / 255, blue: 0xA0 / 255))
        }

        HStack(spacing: 10) {
            Button(Loc.get("Common_Cancel"), action: onClose)
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))
                .disabled(busy)

            Button(action: send) {
                if busy {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Text(Loc.get("Album_ReportSubmit"))
                }
            }
            .buttonStyle(RPMGlassButton(.primary, radius: 10, height: 42, size: 14))
            .disabled(busy)
        }
    }

    private func send() {
        guard !busy else { return }

        busy = true
        said = nil
        typing = false

        Task {
            let trouble = await onSend(note.trimmingCharacters(in: .whitespacesAndNewlines))
            busy = false

            if let trouble {
                said = trouble
            } else {
                sent = true
            }
        }
    }
}
