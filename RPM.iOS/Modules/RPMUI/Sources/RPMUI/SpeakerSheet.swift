import SwiftUI
import RPMCast
import RPMKit

/// Where the sound goes.
///
/// It has the same shape as `RPM.Mobile/Presentation/Controls/CastPicker.xaml`: the handset at
/// the top, then whatever answered, with the room that is playing marked.
///
/// **A speaker that has been paired is still in this list and will refuse.** It keeps
/// advertising itself as a normal speaker, and Google does not allow casting to a member of a
/// pair, so the group beside it is the one that works. Nothing here can tell them apart before
/// trying, which is why the refusal message says what to do about it and not what went wrong.
public struct SpeakerSheet: View {
    private let speakers: [CastDevice]
    private let playingOn: CastDevice?
    private let looking: Bool
    private let trouble: String?
    private let onPick: (CastDevice) -> Void
    private let onHandset: () -> Void
    private let onAgain: () -> Void
    private let onClose: () -> Void

    public init(speakers: [CastDevice], playingOn: CastDevice?, looking: Bool,
                trouble: String?,
                onPick: @escaping (CastDevice) -> Void,
                onHandset: @escaping () -> Void,
                onAgain: @escaping () -> Void,
                onClose: @escaping () -> Void) {
        self.speakers = speakers
        self.playingOn = playingOn
        self.looking = looking
        self.trouble = trouble
        self.onPick = onPick
        self.onHandset = onHandset
        self.onAgain = onAgain
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0x99 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            panel
                .frame(width: 320)
                .rpmGlassCard(radius: 18)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

            rooms

            if let trouble {
                Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

                Text(trouble)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.red)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(Loc.get("Rpm_Cast_Title"))
                .font(RPMFont.displayBold(15))
                .foregroundStyle(.white)

            Spacer()

            if looking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(RPMInk.white(0x88 / 255))
                    .scaleEffect(0.7)
            } else {
                Button { onAgain() } label: {
                    Text(Glyph.refresh)
                        .font(RPMFont.icon(13))
                        .foregroundStyle(RPMInk.white(0x88 / 255))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.get("Rpm_Cast_LookAgain"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var rooms: some View {
        if speakers.isEmpty, !looking {
            // Two things it could be, and only one of them is worth acting on, so the sentence
            // covers both without guessing between them.
            Text(Loc.get("Rpm_Cast_NoneNearby"))
                .rpmKicker()
                .multilineTextAlignment(.center)
                .padding(18)
                .frame(maxWidth: .infinity)
        } else {
            // The handset is a row like any other, and it is always there: it is how somebody
            // takes the sound back.
            ShortScroll(rows: speakers.count + 1, each: 48, upTo: 300) {
                LazyVStack(spacing: 0) {
                    Button(action: onHandset) {
                        line(name: Loc.get("Rpm_Cast_ThisPhone"), said: nil,
                             glyph: Glyph.phone, on: playingOn == nil)
                    }
                    .buttonStyle(RowPress())

                    ForEach(speakers) { speaker in
                        Button { onPick(speaker) } label: {
                            line(name: speaker.name,
                                 // Shown only where it tells somebody something: a group is a
                                 // different kind of place for sound to go, and it is the one
                                 // that works when the speaker beside it refuses.
                                 said: speaker.isGroup ? Loc.get("Rpm_Cast_Group") : nil,
                                 glyph: Glyph.speaker,
                                 on: playingOn?.id == speaker.id)
                        }
                        .buttonStyle(RowPress())
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func line(name: String, said: String?, glyph: String, on: Bool) -> some View {
        HStack(spacing: 14) {
            Text(glyph)
                .font(RPMFont.icon(15))
                // White while chosen, and not a colour: the tick at the end of the row is what
                // shows which one is chosen.
                .foregroundStyle(on ? .white : RPMInk.white(0xB3 / 255))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let said {
                    Text(said)
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0x88 / 255))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if on {
                Text(Glyph.check)
                    .font(RPMFont.icon(14))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
