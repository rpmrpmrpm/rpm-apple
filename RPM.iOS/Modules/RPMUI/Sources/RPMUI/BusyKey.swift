import SwiftUI

/// A play key that shows a ring in place of its glyph while the player is waiting, but only
/// after the wait has lasted long enough to notice.
///
/// **The delay matters.** A track on a fast connection starts in about 200 ms. A spinner that
/// appears and disappears in that time looks like a flicker on every tap. After about half a
/// second the person has noticed the wait, and showing nothing would look like a tap that was
/// not received.
///
/// `Player.isBusy` is read from two observed properties, so the key is redrawn when the value
/// changes and nothing needs to poll. The ceiling is a safety limit: whatever happens, the
/// ring must not turn on the screen for ever.
///
/// The key stays active underneath, so a press while it is waiting still reaches the
/// transport. The transport remembers the press and applies it when the track arrives.
struct BusyKey<Key: View>: View {
    /// How long a wait must last before the ring is shown. Long enough that a normal start
    /// never flickers, short enough that a slow start gets a response quickly.
    private static var patience: Duration { .milliseconds(500) }

    /// A safety limit, not a timeout: nothing is cancelled, the key only stops showing the
    /// ring.
    private static var ceiling: Duration { .seconds(30) }

    private let busy: Bool
    private let ring: CGFloat
    private let key: Key

    @State private var showing = false

    init(busy: Bool, ring: CGFloat = 20, @ViewBuilder key: () -> Key) {
        self.busy = busy
        self.ring = ring
        self.key = key()
    }

    var body: some View {
        ZStack {
            // The glyph is made transparent, not removed. If the key changed size, the
            // transport would move under the thumb.
            key.opacity(showing ? 0 : 1)

            if showing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(RPMInk.white(0xE6 / 255))
                    .scaleEffect(ring / 20)
                    .frame(width: ring, height: ring)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showing)
        .task(id: busy) {
            guard busy else { showing = false; return }

            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled else { return }
            showing = true

            try? await Task.sleep(for: Self.ceiling - Self.patience)
            guard !Task.isCancelled else { return }
            showing = false
        }
    }
}
