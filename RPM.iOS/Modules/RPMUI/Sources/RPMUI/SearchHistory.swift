import SwiftUI
import RPMKit

/// What the collection's search was used for, newest first, kept in the user defaults as lines of
/// text. The records wall and the artists page share it.
enum SearchHistory {
    static let key = "search.history"

    /// The most searches kept.
    static let most = 10

    /// How long the box must be left alone before what is in it counts as a search to remember:
    /// the person stopped typing and is reading the results.
    static let settled: Duration = .seconds(2)

    static func entries(_ stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Puts `asked` at the top. A search that only adds to or takes from the newest entry ("radi",
    /// then "radiohead") replaces it, so the half-typed steps of one search are not kept as
    /// separate entries.
    static func remember(_ asked: String, in stored: String) -> String {
        let clean = asked.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard clean.count >= 2 else { return stored }
        var list = entries(stored)
        if let newest = list.first,
           clean.lowercased().hasPrefix(newest.lowercased()) || newest.lowercased().hasPrefix(clean.lowercased()) {
            list.removeFirst()
        }
        list.removeAll { $0.caseInsensitiveCompare(clean) == .orderedSame }
        return ([clean] + list).prefix(most).joined(separator: "\n")
    }

    static func forget(_ asked: String, in stored: String) -> String {
        entries(stored).filter { $0 != asked }.joined(separator: "\n")
    }
}

extension View {
    /// Remembers `asked` in the search history once it has stayed the same for
    /// ``SearchHistory/settled``. Nothing while `searching` is false.
    func remembersSearch(_ asked: String, searching: Bool) -> some View {
        modifier(RemembersSearch(asked: asked, searching: searching))
    }
}

private struct RemembersSearch: ViewModifier {
    let asked: String
    let searching: Bool
    @AppStorage(SearchHistory.key) private var stored = ""

    func body(content: Content) -> some View {
        content.task(id: searching ? asked : "") {
            guard searching, asked.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
            try? await Task.sleep(for: SearchHistory.settled)
            guard !Task.isCancelled else { return }
            stored = SearchHistory.remember(asked, in: stored)
        }
    }
}

/// The earlier searches, newest first, shown under the box while it is empty. A tap puts one back
/// in the box; the cross beside it removes it, and Clear removes them all.
struct SearchHistoryList: View {
    let onPick: (String) -> Void

    @AppStorage(SearchHistory.key) private var stored = ""

    var body: some View {
        DissolvingScroll {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(Loc.get("Rpm_Search_Recent")).rpmKicker()
                    Spacer()
                    Button(Loc.get("Rpm_Search_ClearRecent")) { stored = "" }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RPMInk.white(0xB8 / 255))
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                }

                ForEach(SearchHistory.entries(stored), id: \.self) { asked in
                    HStack(spacing: 12) {
                        Text(Glyph.search)
                            .font(RPMFont.icon(12))
                            .foregroundStyle(RPMInk.white(0x77 / 255))
                        Text(asked)
                            .font(RPMFont.display(15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { stored = SearchHistory.forget(asked, in: stored) } label: {
                            Text(Glyph.close)
                                .font(RPMFont.icon(11))
                                .foregroundStyle(RPMInk.white(0x77 / 255))
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Loc.get("Rpm_Search_Forget"))
                    }
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(asked) }
                }
            }
            .padding(.leading, RPMLayout.margin)
            .padding(.trailing, 12)
            .padding(.top, 4)
            .padding(.bottom, RPMLayout.foot)
        }
        .scrollIndicators(.hidden)
    }
}
