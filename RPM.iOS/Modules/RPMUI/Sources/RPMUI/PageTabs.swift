import SwiftUI
import RPMKit

/// One tab of a ``PageTabs`` row: its name and its mark.
///
/// The library's views (``LibraryMode``) and the settings page's sections (``SettingsSection``)
/// are both shown with this row.
protocol PageTab: Hashable, CaseIterable where AllCases == [Self] {
    associatedtype Mark: View

    @MainActor var label: String { get }

    /// The mark on the key. It is a view and not a glyph string, because some marks are not
    /// drawn from the icon font.
    @MainActor @ViewBuilder var mark: Mark { get }
}

/// The row of tabs under a page's header that switches between the parts of the page.
///
/// It is the app's tab capsule at a smaller size, with the same glass. Only the selected tab shows
/// its name beside its mark. The others show the mark alone, so five tabs fit in every language.
/// The pill slides to the tab chosen, that tab opens as its name fades in, and the one left closes
/// as its name fades out, all on the tab bar's spring.
///
/// **Each library view draws its own row, so the row remembers where the last one stood**
/// (``lastShown``). The row of the view that comes in starts at the tab the last row showed and
/// moves from there, while the two views fade into one another. A row that started at its own
/// tab would arrive already finished. Each kind of tab is remembered on its own.
struct PageTabs<Choice: PageTab>: View {
    @Binding private var mode: Choice

    /// The tab the row is showing, as far as the motion has got: it follows ``mode`` on the spring.
    @State private var shown: Choice

    init(_ mode: Binding<Choice>) {
        _mode = mode
        _shown = State(initialValue: Self.lastShown ?? mode.wrappedValue)
    }

    /// The tab the last row of this kind on screen showed, for the row that replaces it.
    @MainActor private static var lastShown: Choice? {
        get { PageTabsMemory.last[ObjectIdentifier(Choice.self)]?.base as? Choice }
        set { PageTabsMemory.last[ObjectIdentifier(Choice.self)] = newValue.map(AnyHashable.init) }
    }

    /// A closed tab is as wide as its mark's box; the open one takes the rest.
    private static var unlit: CGFloat { 52 }
    private static var tall: CGFloat { 32 }

    /// The tab bar's spring.
    private static var motion: Animation { .spring(response: 0.35, dampingFraction: 0.8) }

    var body: some View {
        GeometryReader { box in
            let all = Choice.allCases
            let lit = max(Self.unlit, box.size.width - Self.unlit * CGFloat(all.count - 1))
            let at = CGFloat(all.firstIndex(of: shown) ?? 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(RPMInk.white(0x24 / 255))
                    .frame(width: lit, height: Self.tall)
                    .offset(x: Self.unlit * at)

                HStack(spacing: 0) {
                    ForEach(all, id: \.self) { choice in
                        key(choice, lit: lit)
                    }
                }
            }
        }
        .frame(height: Self.tall)
        .padding(3)
        .rpmGlass(Capsule())
        .padding(.horizontal, RPMLayout.margin)
        // Space between the capsule and the first row below it, which scrolls up under the
        // capsule.
        .padding(.bottom, 16)
        .onAppear {
            Self.lastShown = mode
            if shown != mode { withAnimation(Self.motion) { shown = mode } }
        }
        .onChange(of: mode) { _, now in
            Self.lastShown = now
            withAnimation(Self.motion) { shown = now }
        }
    }

    /// One tab: its mark, and its name while it is open. The name is clipped by the tab as the tab
    /// opens and closes, and fades with it.
    private func key(_ choice: Choice, lit: CGFloat) -> some View {
        let open = choice == shown

        return Button {
            guard mode != choice else { return }
            Haptics.pick()
            Self.lastShown = mode
            mode = choice
        } label: {
            HStack(spacing: 0) {
                choice.mark
                    .foregroundStyle(open ? .white : RPMInk.white(0x99 / 255))

                // The system font and not Cabin, as the tab bar's names.
                Text(choice.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .fixedSize()
                    .frame(width: open ? nil : 0, alignment: .leading)
                    .clipped()
                    .opacity(open ? 1 : 0)
            }
            .frame(width: open ? lit : Self.unlit, height: Self.tall)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(mode == choice ? .isSelected : [])
    }
}

/// Where the last row of each kind of tab stood, by the type of its tabs. A generic type cannot
/// keep a static stored property, so ``PageTabs`` keeps it here.
@MainActor
private enum PageTabsMemory {
    static var last: [ObjectIdentifier: AnyHashable] = [:]
}
