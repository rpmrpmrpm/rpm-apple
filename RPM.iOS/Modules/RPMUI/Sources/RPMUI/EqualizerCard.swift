import SwiftUI
import RPMKit
import RPMAudio

/// The equaliser, on the Playback settings under volume levelling. It is laid out as the desktop's
/// Sound settings lay it out, as the Android phone does: whose curve it is, the switch, the presets
/// and Flat, then the pre-amp and the ten bands as upright faders from -12 to +12 dB in whole steps.
/// The card has its controls only, with no description line. Under the faders, a warning in red
/// shows while the curve clips (``EqCurve/clips``).
///
/// It reads ``EqualizerSettings`` from the environment, and shows nothing where there is none.
struct EqualizerCard: View {
    @Environment(EqualizerSettings.self) private var eq: EqualizerSettings?

    /// Upright sliders, as the faders stand upright too. The sliders on their side already mark the
    /// General section. The same glyph as the Android phone's equaliser card.
    private static let glyph = "\u{f3f1}"

    var body: some View {
        if let eq, let output = eq.output {
            SettingsCardFrame(Self.glyph, Loc.get("Settings_Eq")) {
                // Whose curve this is. The faders move by themselves when the music moves to other
                // speakers. Without this line, that would look like the app forgetting the settings.
                Text(output.label.map { Loc.get("Settings_EqFor", $0) } ?? Loc.get("Settings_EqForCast"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xCC / 255))

                Toggle(isOn: Binding(get: { eq.curve.on },
                                     set: { on in eq.change(eq.curve.turned(on)) })) {
                    Text(Loc.get("Settings_EqOn"))
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0xB3 / 255))
                }
                .rpmControlTint()
                .onChange(of: eq.curve.on) { _, _ in Haptics.pick() }

                HStack(spacing: 10) {
                    presets(eq)

                    Button(Loc.get("Settings_EqReset")) { eq.change(eq.curve.flattened()) }
                        .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 34,
                                                    stretches: false, inset: 16, size: 13))
                }

                EqFaders(curve: eq.curve) { eq.change($0) }

                // The bands push the loudest sounds past full scale. A new curve lowers the pre-amp
                // by itself (``EqualizerSettings/change(_:)``), so this shows when the listener
                // raises the pre-amp again, or when a curve needs more room than -12 dB gives.
                if eq.curve.clips {
                    Text(Loc.get("Settings_EqClipWarning"))
                        .font(RPMFont.display(11))
                        .foregroundStyle(RPMInk.red)
                }
            }
        }
    }

    /// The preset menu. It shows the preset the bands match, or "Preset" when they match none.
    private func presets(_ eq: EqualizerSettings) -> some View {
        let chosen = eq.curve.preset.flatMap { EqPreset.all.firstIndex(of: $0) } ?? -1
        return Menu {
            Picker(Loc.get("Settings_EqPreset"), selection: Binding(
                get: { chosen },
                set: { at in
                    guard EqPreset.all.indices.contains(at) else { return }
                    // A preset is a curve worth hearing, so choosing one turns the equaliser on, as
                    // on the desktop. Picking Bass boost and hearing no change would look broken.
                    eq.change(eq.curve.withPreset(EqPreset.all[at]).turned(true))
                    Haptics.pick()
                })) {
                ForEach(EqPreset.all.indices, id: \.self) { at in
                    Text(Loc.get(EqPreset.all[at].nameKey)).tag(at)
                }
            }
        } label: {
            closedMenu(EqPreset.all.indices.contains(chosen) ? Loc.get(EqPreset.all[chosen].nameKey)
                                                             : Loc.get("Settings_EqPreset"))
        }
    }

    /// A closed menu, drawn as the settings page draws its menus (`SettingsPage.closedMenu`): the
    /// choice in a dark field, with the up-down mark that shows it can be opened.
    private func closedMenu(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(RPMFont.display(15))
                .lineLimit(1)
            Spacer()
            Text(Glyph.sort).font(RPMFont.icon(11))
        }
        .foregroundStyle(RPMInk.white(0xF0 / 255))
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            let well = RoundedRectangle(cornerRadius: 8, style: .continuous)
            well.fill(RPMInk.white(0x14 / 255))
                .overlay { well.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
        }
    }
}

/// The pre-amp, then the ten bands, one column each with its label under it, as on the desktop.
/// Dimmed while the equaliser is off: the values are kept but not heard. They can still be moved, as
/// on the desktop.
private struct EqFaders: View {
    let curve: EqCurve
    let onChange: (EqCurve) -> Void

    var body: some View {
        let labels = [Loc.get("Settings_EqPre")] + Equalizer.bands.map { Equalizer.label($0) }
        let values = [curve.preamp] + curve.gains

        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { at in
                VStack(spacing: 4) {
                    EqFader(db: values[at], label: labels[at]) { db in
                        onChange(at == 0 ? curve.withPreamp(db) : curve.withBand(at - 1, db))
                    }
                    Text(labels[at])
                        .font(RPMFont.display(9))
                        .foregroundStyle(RPMInk.white(0x99 / 255))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .opacity(curve.on ? 1 : 0.55)
    }
}

/// One upright fader, from +12 dB at the top to -12 at the bottom, with a line from 0 dB to the knob.
/// A drag or a tap sets the value under the finger, in whole dB. A drag that starts on a fader moves
/// the fader and not the page.
private struct EqFader: View {
    let db: Double
    let label: String
    let onChange: (Double) -> Void

    /// The colour the user chose for the controls. See ``AppColour``.
    @AppStorage(AppColour.key) private var colour = ""

    /// The height of a fader: the desktop's 110 points plus room for the knob.
    private static let tall: CGFloat = 130

    /// The knob's radius, which is also how far in from each end the track runs.
    private static let knob: CGFloat = 7

    private static var most: Double { Equalizer.maxGain }

    var body: some View {
        let lit = AppColour.shown(colour) ?? Color.white.opacity(0xCC / 255)

        return Canvas { context, size in
            let inset = Self.knob
            let x = size.width / 2
            let span = size.height - 2 * inset
            func y(_ value: Double) -> CGFloat {
                inset + CGFloat((Self.most - value) / (2 * Self.most)) * span
            }
            let track = Color.white.opacity(0x26 / 255)

            var line = Path()
            line.move(to: CGPoint(x: x, y: inset))
            line.addLine(to: CGPoint(x: x, y: size.height - inset))
            context.stroke(line, with: .color(track), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // The 0 dB mark, a short line across.
            var tick = Path()
            tick.move(to: CGPoint(x: x - 5, y: y(0)))
            tick.addLine(to: CGPoint(x: x + 5, y: y(0)))
            context.stroke(tick, with: .color(track), lineWidth: 1)

            var raised = Path()
            raised.move(to: CGPoint(x: x, y: y(0)))
            raised.addLine(to: CGPoint(x: x, y: y(db)))
            context.stroke(raised, with: .color(lit),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            let knob = CGRect(x: x - inset, y: y(db) - inset, width: inset * 2, height: inset * 2)
            context.fill(Path(ellipseIn: knob), with: .color(.white))
        }
        .frame(height: Self.tall)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { drag in send(Self.value(at: drag.location.y)) }
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        // "dB" is the unit's symbol, the same in every language.
        .accessibilityValue(Text(verbatim: "\(Int(db)) dB"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: send(db + 1)
            case .decrement: send(db - 1)
            @unknown default: break
            }
        }
    }

    private func send(_ value: Double) {
        let next = min(max(value, -Self.most), Self.most)
        guard next != db else { return }
        Haptics.tick()
        onChange(next)
    }

    /// The value in whole dB at height `y` of the fader.
    private static func value(at y: CGFloat) -> Double {
        let share = min(max((y - knob) / (tall - 2 * knob), 0), 1)
        return (most - Double(share) * 2 * most).rounded()
    }
}
