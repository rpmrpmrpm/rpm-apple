import SwiftUI
import RPMKit
import RPMSharedUI

/// The mark beside a supporter's name: a heart and a word, in gold.
///
/// Matches the desktop's `SupporterBadge`. The colours come from ``SupporterMetal``,
/// which the Apple TV badge also uses.
///
/// **It has no "not a supporter" state.** The caller either shows it or does not, so
/// the view has no idle look of its own.
struct SupporterMark: View {
    /// The word beside the heart. If it is empty, only the heart is drawn, for a line
    /// that has no room for the word.
    private let word: String

    init(word: String = Loc.get("Rpm_Profile_PlanSupporter")) { self.word = word }

    var body: some View {
        let pill = RoundedRectangle(cornerRadius: 9, style: .continuous)

        return HStack(spacing: 6) {
            Text(Glyph.heart)
                .font(RPMFont.icon(9))

            if !word.isEmpty {
                Text(word)
                    .font(.system(size: 10))
            }
        }
        .foregroundStyle(SupporterMetal.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background { pill.fill(SupporterMetal.face) }
        .overlay { pill.strokeBorder(SupporterMetal.rim, lineWidth: 1) }
        .accessibilityLabel(Loc.get("Rpm_Profile_PlanSupporter"))
    }
}
